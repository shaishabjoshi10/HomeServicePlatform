/// Single source of truth for the backend's base URL.
///
/// Exactly ONE of the lines below should be uncommented at a time —
/// comment out whichever you're not using.
///
/// - Android emulator -> host machine: http://10.0.2.2:PORT
/// - iOS simulator: http://localhost:PORT
/// - Physical device (same Wi-Fi as your computer): http://<your-machine-LAN-IP>:PORT
///
/// Update this one constant if your backend's host/port changes — every
/// service (auth, providers, etc.) reads from here.

// Emulator / iOS simulator:
// const String apiBaseUrl = 'http://10.0.2.2:8000';

// Physical device — replace with your computer's actual LAN IP, then
// comment out the emulator line above and uncomment this one instead:
const String apiBaseUrl = "http://192.168.1.75:8000";