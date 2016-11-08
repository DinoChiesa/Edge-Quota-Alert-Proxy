// checkAlerts.js
// ------------------------------------------------------------------
//
// Checks the Apigee Edge cache for cached alerts.
//
// created: Fri Sep 16 14:47:31 2016
// last saved: <2016-November-08 09:21:36>

var assert = require('assert'),
    async = require('async'),
    apigee = require('apigee-access'),
    cacheScope = 'application',
    cacheName = 'cache1',
    express = require('express'),
    cacheKeySeparator = "__",
    bodyParser = require('body-parser'),
    app = express(),
    log = new LightLog();

function LightLog(id) { }

LightLog.prototype.write = function(str) {
  var time = (new Date()).toString(), me = this;
  console.log('[' + time.substr(11, 4) + '-' +
              time.substr(4, 3) + '-' + time.substr(8, 2) + ' ' +
              time.substr(16, 8) + '] ' + str );
};

function getType(obj) {
  return Object.prototype.toString.call(obj);
}

function decreasingByThreshold(a,b) {
  if (a.threshold > b.threshold) return -1;
  if (a.threshold < b.threshold) return 1;
  return 0;
}

function checkPendingAlerts(request, cb) {
  var results = { errors: [], alerts: [], noalerts: []};
  var info = apigee.getVariable(request, 'verifyapikey.VerifyApiKey-1.apiproduct.quota_alerts_info');
  var config = JSON.parse(info);
  if ( ! config) {
    results.errors.push("config is null");
    cb(null, results);
    return;
  }

  config.sort(decreasingByThreshold);
  var apikeys = request.body.apikeys; // array
  var cache = apigee.getCache('', { resource: cacheName, scope: cacheScope } );

  async.eachSeries(apikeys, getCheckerForKey(config, cache, results),
                   function(e){
                     if (e) {
                       cb(e, null);
                     }
                     else {
                       cb(null, results);
                     }
                   });

}


function getCheckerForKey(config, cache, results) {
  return function(apikey, cb) {

    function checkOneThreshold(c, cb) {
      // c = {
      //      threshold: 65,
      //      message : "----message string here ---",
      //      subject : ".....",
      //      sendto : "----email address ---",
      //      cc : "----email address ---",
      //      from : "----email address ---"
      //    }

      var cacheKey = ['alertpending', apikey, c.threshold].join(cacheKeySeparator);
      log.write('cache key: ' + cacheKey);

      cache.get(cacheKey, function(error, data){
        if (error) {
          log.write('error retrieving cache...' + error);
          results.errors.push('while retrieving cachekey: ' + cacheKey + ', error: ' +error);
          cb(null);
          return;
        }

        if (data) {
          data = JSON.parse(data);
          if ( ! data.sent) {
            data.threshold = c.threshold;
            data.cacheKey = cacheKey;
            results.alerts.push(data);
            var now = new Date();
            var ttl = (data.alert_expires_ms - now.getTime()) / 1000;
            data.sent = now.getTime(); // flag that the alert was "sent"
            cache.put(cacheKey, JSON.stringify(data), ttl, function(error, data){
              if (error) {
                log.write('error retrieving cache...' + error);
                results.errors.push('while replacing cached item: ' + cacheKey + ', error: ' + error);
              }
              cb(null);
            });
          }
          else {
            data.cacheKey = cacheKey;
            results.alerts.push(data);
            cb(null);
          }
          return;
        }

        results.noalerts.push(cacheKey);
        cb(null);
      });
    }

    async.eachSeries(config, checkOneThreshold, cb);

  };
}



// parse application/json
app.use(bodyParser.json());

app.post('/check', function(request, response) {
  checkPendingAlerts(request, function(e, results) {
    if (e) {
      var e2 = {
            error: true,
            message: e.message,
            stack: e.stack
          };
      response.status(500).send(JSON.stringify(e2, null, 2)+'\n');
      return;
    }
    // This is where we'd send alerts out. If there is an alert for multiple
    // thresholds, send only the alert for the highest threshold. Could use some
    // API-driven mail service. For now, no sending.  Just reply to the API call
    // with a payload of pending alerts.  These remain pending until cache expiry.
    response.header('Content-Type', 'application/json');
    response.status(200).send(JSON.stringify(results, null, 2) + '\n');
  });
});


// catch all
app.use(function(request, response) {
  response.header('Content-Type', 'application/json');
  var r = {
        error: 404,
        status : "This is not the server you\'re looking for.",
        urlpath: request.originalUrl,
        method: request.method
      };
  response.status(404).send(JSON.stringify(r, null, 2) + '\n');
});


port = process.env.PORT || 5950;
app.listen(port, function() {
  log.write('listening...');
});
