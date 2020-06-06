import 'package:beautifulsoup/beautifulsoup.dart';
import 'package:requests/requests.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nauta_api/src/utils/exceptions.dart';

class SessionObject {
  String loginAction;
  String csrfhw;
  String wlanuserip;
  String attributeUuid;
  static Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  SessionObject(
      {this.loginAction, this.csrfhw, this.wlanuserip, this.attributeUuid});

  bool isLoggedIn() {
    return (attributeUuid != null);
  }

  Future<void> save() async {
    final SharedPreferences prefs = await _prefs;

    prefs.setString('nauta_login_action', loginAction);
    prefs.setString('nauta_csrfhw', csrfhw);
    prefs.setString('nauta_wlanuserip', wlanuserip);
    prefs.setString('nauta_attribute_uuid', attributeUuid);
  }

  static Future<SessionObject> load() async {
    final SharedPreferences prefs = await _prefs;

    return SessionObject(
      loginAction: prefs.getString('nauta_login_action'),
      csrfhw: prefs.getString('nauta_csrfhw'),
      wlanuserip: prefs.getString('nauta_wlanuserip'),
      attributeUuid: prefs.getString('nauta_attribute_uuid')
    );
  }

  Future<void> dispose() async {
    final SharedPreferences prefs = await _prefs;

    prefs.remove('nauta_login_action');
    prefs.remove('nauta_csrfhw');
    prefs.remove('nauta_wlanuserip');
    prefs.remove('nauta_attribute_uuid');
  }
}

class NautaProtocol {
  static const CHECK_PAGE = "http://www.cubadebate.cu";

  static SessionObject session;

  static Map<String, String> _getInputs(Beautifulsoup formSoup) {
    final inputs = formSoup.find_all('input');

    final data = Map<String, String>();

    final entries = inputs
        .map((e) => MapEntry(e.attributes['name'], e.attributes['value']));

    data.addEntries(entries);

    return data;
  }

  static Future<bool> isConnected() async {
    final r = await Requests.get(CHECK_PAGE);

    return !(r.content().contains('secure.etecsa.net'));
  }

  static bool isLoggedIn() {
    return (session != null && session.isLoggedIn());
  }

  static Future<SessionObject> createSession() async {
    if (await isConnected()) {
      if (isLoggedIn()) {
        throw NautaPreLoginException("Hay una session abierta");
      } else {
        throw NautaPreLoginException("Hay una conexion activa");
      }
    }

    session = SessionObject();

    var resp = await Requests.get('http://1.1.1.1/');

    if (resp.statusCode != 200) {
      throw NautaPreLoginException('Failed to create session');
    }

    var soup = Beautifulsoup(resp.content());
    final action = soup('form').attributes['action'];
    var data = _getInputs(soup);

    // Now go to the login page
    resp = await Requests.post(action,
        body: data, bodyEncoding: RequestBodyEncoding.FormURLEncoded);

    soup = Beautifulsoup(resp.content());

    session.loginAction = soup.find_all('form')[1].attributes['action'];
    data = _getInputs(soup);

    session.csrfhw = data['CSRFHW'];
    session.wlanuserip = data['wlanuserip'];

    return session;
  }

  static Future<String> login(
      SessionObject session, String username, String password) async {
    final r = await Requests.post(session.loginAction,
        body: {
          "CSRFHW": session.csrfhw,
          "wlanuserip": session.wlanuserip,
          "username": username,
          "password": password
        },
        bodyEncoding: RequestBodyEncoding.FormURLEncoded);

    final redirectUrl = r.headers['location'];

    final res = await Requests.get(redirectUrl);

    res.raiseForStatus();
    final data = res.content();

    final regExp = RegExp(r'ATTRIBUTE_UUID=(\w+)&CSRFHW=');

    final matches = regExp.allMatches(data);

    if (matches.length > 0)
      return matches.elementAt(0).group(1);
    else
      throw NautaLoginException('No se pudo obtener ATTRIBUTE_UUID');
  }

  static Future<bool> logout(SessionObject session, String username) async {
    final logoutUrl = "https://secure.etecsa.net:8443/LogoutServlet?" +
        "CSRFHW=${session.csrfhw}&" +
        "username=$username&" +
        "ATTRIBUTE_UUID=${session.attributeUuid}&" +
        "wlanuserip=${session.wlanuserip}";

    final r = await Requests.get(logoutUrl);
    r.raiseForStatus();

    return r.statusCode == 200;
  }
}

class NautaClient {
  final String user;
  final String password;
  SessionObject session;

  NautaClient({this.user, this.password});

  Future<void> initSession() async {
    session = await NautaProtocol.createSession();
    await session.save();
  }

  bool isLoggedIn() {
    return NautaProtocol.isLoggedIn();
  }

  Future<void> login() async {
    if (session == null) {
      await initSession();
    }

    session.attributeUuid = await NautaProtocol.login(session, user, password);
    await session.save();
  }

  Future<void> logout() async {
    try {
      await NautaProtocol.logout(session, user);
      await session.dispose();
      session = null;
    }
    catch (e) {
      throw NautaLogoutException('No se puede cerrar la seccion');
    }
  }

  void loadLastSession() async {
      session = await SessionObject.load();
  }
}