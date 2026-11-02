export default class Logger {
  debug() {}
  info() {}
  warn(...args) {console.warn(...args)}
  error(...args) {console.error(...args)}
}
