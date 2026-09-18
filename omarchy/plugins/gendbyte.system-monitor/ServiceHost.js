function hostedService(bar) {
  var shell = bar ? bar.shell : null
  if (!shell || typeof shell.serviceFor !== "function") return null
  return shell.serviceFor("gendbyte.system-monitor") || null
}

if (typeof module !== "undefined") {
  module.exports = { hostedService: hostedService }
}
