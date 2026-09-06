/// The *type* of local network interface available. This is deliberately
/// distinct from internet reachability - a device can have `wifi` and still
/// have no internet access (see README "Network Detection").
enum LocalConnectivity { wifi, mobile, ethernet, none }
