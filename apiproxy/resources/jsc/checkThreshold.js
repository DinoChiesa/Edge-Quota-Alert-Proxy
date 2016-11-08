// checkThreshold.js
// ------------------------------------------------------------------
//
// Maybe set a context variable if a threshold has been exceeded.
//
// This callout checks the alert settings stored in a context variable.
// (Presumed to have been loaded from KVM, or from custom attribute on
// an API Product).
//
// The alert settings is a JSON string, and must be passed to
// JSON.parse() before being evaluated.  After that, it is an array of
// threshold objects, like this:
//
//  [ {
//      threshold: 65,
//      message : "----message string here ---",
//      subject : ".....",
//      sendto : "----email address ---",
//      cc : "----email address ---",
//      from : "----email address ---"
//    },
//    ...
//  ]
//
// Each item in the array is an object with a "threshold"
// property which is an integer, and a set of other string properties,
// which can have any name. But the pattern above is a good one to
// follow for email alerts.
//
// This callout does this:
//
//   1. computes the actual usage percentage as a number 0..100
//      and sets a context variable with that value.
//
//   2. sorts the threshold objects by the value of the threshold
//      property, highest to lowest.
//
//   3. if any threshold has been exceeded, sets "threshold_exceeded" context variable.
//
// Friday, 16 September 2016, 12:48
//

var quotaPolicyName = properties['quota-policy-name'],
    alertVarName = properties['threshold-alert-info'],
    cacheExpiry = properties['cache-expiry-hours-after-midnight'] || 9,
    thresholdVarName = properties['threshold-var'] || 'highest_threshold_reached',
    usedCount = parseInt(context.getVariable('ratelimit.'+quotaPolicyName +'.used.count'), 10),
    allowedCount = parseInt(context.getVariable('ratelimit.'+quotaPolicyName +'.allowed.count'), 10),
    actualPct = 100 * (usedCount / allowedCount || 0),
    x = context.getVariable(alertVarName);

function decreasingByThreshold(a,b) {
  if (a.threshold > b.threshold) return -1;
  if (a.threshold < b.threshold) return 1;
  return 0;
}

function computeQuotaExpiryInSeconds() {
  var t = Number(context.getVariable('system.timestamp')),
      e = context.getVariable('ratelimit.'+quotaPolicyName+'.expiry.time'),
      delta = Math.abs(e - t) / 1000;
  return delta.toFixed(0);
}

function computeQuotaExpiryInSeconds() {
  var t = Number(context.getVariable('system.timestamp')),
      e = context.getVariable('ratelimit.'+quotaPolicyName+'.expiry.time'),
      delta = Math.abs(e - t) / 1000;
  return delta.toFixed(0);
}

function getMidnightUTC_milliseconds() {
  var rightNow = new Date(),
      midnightUtcMs = Date.UTC(rightNow.getFullYear(),
                             rightNow.getMonth(),
                             rightNow.getDate() + 1, // the next day, ...
                             0, 0, 0 // ...at 00:00:00 hours
                              );
  return midnightUtcMs;
}


function computeSecondsTilMidnightUTC() {
  var rightNow = new Date(),
      midnightUtcMs = Date.UTC(rightNow.getFullYear(),
                             rightNow.getMonth(),
                             rightNow.getDate() + 1, // the next day, ...
                             0, 0, 0 // ...at 00:00:00 hours
                            ),
      secondsTilMidnightUtc = (midnightUtcMs - rightNow.getTime()) / 1000;

  return secondsTilMidnightUtc;
}

context.setVariable('quota_usage_pct', actualPct.toFixed(0));

if (x && x !== '') {
  var config = JSON.parse(x);
  config.sort(decreasingByThreshold);

  // print('config.length: ' + config.length);
  // print('cachedAlerts: ' + JSON.stringify(cachedAlerts));

  for (var i=0, L=config.length; i<L; i++){
    var a=config[i];
    if (actualPct >= a.threshold) {
      context.setVariable(thresholdVarName, a.threshold + '');
      context.setVariable('quota_expiresin', computeQuotaExpiryInSeconds());
      // set variables to indicate when the  alert expires.
      // This script uses a configurable number of hours after midnight UTC.

      // Relative seconds, in other words, "seconds from now"
      context.setVariable('quota_alert_expiresin',
                          (computeSecondsTilMidnightUTC() + (cacheExpiry * 3600)).toFixed(0));

      // Absolute time of expiry in milliseconds-since-epoch
      context.setVariable('quota_alert_expires_ms',
                          (getMidnightUTC_milliseconds() + (cacheExpiry * 3600 * 1000)).toFixed(0));
      i=L; // terminate loop
    }
  }
}
