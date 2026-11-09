/// Address of a GR camera on its own Wi-Fi access point: it serves its
/// HTTP API, change WebSocket and live view there (research/protocol/
/// http-api.md §1; the GR IV's `start_wlan.sh` assigns it to `uap0`,
/// connection-lifecycle.md).
const grCameraHost = '192.168.0.1';

/// Port of the camera's HTTP API, change WebSocket and live view: plain
/// `http://` and `ws://` URLs without a port (research/protocol/
/// http-api.md §1).
const grCameraHttpPort = 80;
