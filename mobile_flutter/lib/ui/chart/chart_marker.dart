/// The four levels a trader can pin on a chart.
///
/// It lives in its own file because both the chart screen and the painter ask
/// for it: the screen owns which level is active and the painter decides how it
/// is drawn. Keeping it here is what let the painter move out of the 4,000-line
/// screen file without the two importing each other.
enum Marker { entry, stop, take, exit }
