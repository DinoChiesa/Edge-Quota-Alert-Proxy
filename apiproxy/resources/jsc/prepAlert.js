// prepAlert.js
// ------------------------------------------------------------------
//
// Populates the data to be set in an alert.
//
// There is a Quota alert threshold configuration specified as a JSON string,
// presumably in KVM or a custom attribute on an API product.  It must be passed
// to JSON.parse() before being evaluated.  After that, it is an array of
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
// Each item in the array is an object with a "threshold" property which is an
// integer, and a set of other string properties, which can have any name. But the
// pattern above is a good one to follow for email alerts.
//
// This callout does this:
//
//   1. retrieves the configured threshold_info for the max reached threshold
//
//   2. elaborates the templates contained there using the current message context.
//
//   3. sets context variables for each elaborated template.
//
// The string properties in the threshold configuration info are each treated as
// templates. When a fragment like {foo} is found within any string property, this
// callout replaces the fragment with the value of the context variable named
// foo. For example, "hello {developer.name}" results in a string "hello Charlie"
// if the context variabled named "developer.name" has the value "Charlie".
//
// These variables can then be used by subsequent policies in the flow, such as
// AssignMessage, to send an email or other alert. Rather than sending an email
// directly, this bundle uses PopulateCache, to allow asynch sending of alerts, so
// as to prevent duplicate notifications in a distributed environment.
//
//
// Friday, 16 September 2016, 13:11
//

var thresholdVarName = properties['threshold-var'],
    alertVarName = properties['threshold-alert-info'],
    varPrefix = properties['var-prefix'] + '',
    threshold = context.getVariable(thresholdVarName),
    x = context.getVariable(alertVarName),
    re1 = new RegExp('(.*)(?!{{){([^{}]+)(?!}})}(.*)'),
    re2 = new RegExp('(.*){{([^{}]+)}}(.*)'); // for double-curlies

if (varPrefix === 'undefined') { varPrefix = 'alert_'; }
if (thresholdVarName === 'undefined') { thresholdVarName = 'highest_threshold_reached'; }

function replaceVariables(s) {
  var match, curValue, v;

  // replace all variables in the string
  for (curValue = s, match = re1.exec(curValue); match; match = re1.exec(curValue)){
    v = context.getVariable(match[2]) || '???';
    curValue = match[1] + v + match[3];
  }
  // replace double-curlies with single-curlies.
  for (match = re2.exec(curValue); match; match = re2.exec(curValue)){
    curValue = match[1] + '{' + match[2] + '}' + match[3];
  }
  return curValue;
}

function isString(a) {
  return (Object.prototype.toString.call(a) === "[object String]");
}

function decreasingByThreshold(a,b) {
  if (a.threshold > b.threshold) return -1;
  if (a.threshold < b.threshold) return 1;
  return 0;
}

function matchingThreshold(x) {
  return function(element, index) {
    return (element.threshold + '' === x);
  };
}

context.setVariable(varPrefix + "threshold", threshold);

if (x && x !== '') {
  var config = JSON.parse(x);
  var match = config.find(matchingThreshold(threshold));
  var resultingHash = {};
  if (match) {
    for (var p in match) {
      // do template replacement for each string
      if (match.hasOwnProperty(p) && isString(match[p])) {
        var v = replaceVariables(match[p]);
        context.setVariable(varPrefix + p, v);
        resultingHash[p] = v;
      }
    }
    resultingHash.alert_expires_ms = context.getVariable('quota_alert_expires_ms');
    context.setVariable(varPrefix + "alert", JSON.stringify(resultingHash));
    //print(p + ': ' + v);
  }
  else {
    context.setVariable(varPrefix + "nomatch", "true");
  }
}
else {
  context.setVariable(varPrefix + "missing_alert_info", "true");
}
