#! /usr/local/bin/node
/*jslint node:true */

// gen-compact-form.js
// ------------------------------------------------------------------
//
// Description goes here....
//
// created: Fri Sep 16 14:12:23 2016
// last saved: <2016-November-08 10:38:46>

var fs = require('fs');

// Example sample configuration:
//
// [{
//   "threshold": 65,
//   "message": "Dear {developer.firstname} {developer.lastname}, on {system.time}, your app, {developer.app.name}, reached {quota_usage_pct}% of the alotted quota. Sincerely, The Mgmt.",
//   "subject": "API usage alert for {developer.app.name}",
//   "sendto": "{developer.email}",
//   "from": "DChiesa@apigee.com"
// }, {
//   "threshold": 85,
//   "message": "Dear {developer.firstname} {developer.lastname}, on {system.time}, your app, {developer.app.name}, reached {quota_usage_pct}% of the alotted quota. You really should look into this.",
//   "subject": "API usage alert for {developer.app.name}",
//   "sendto": "{developer.email}",
//   "from": "DChiesa@apigee.com"
// }, {
//   "threshold": 95,
//   "message": "Dear {developer.firstname} {developer.lastname}, on {system.time}, your app, {developer.app.name}, reached {quota_usage_pct}% of the alotted quota. THE END IS NEAR!",
//   "subject": "API usage alert for {developer.app.name}",
//   "sendto": "{developer.email}",
//   "cc" : "Dino@apigee.com",
//   "from": "DChiesa@apigee.com"
// }]


function main(args) {
  var i = 0;
    try {
      args.forEach(function(arg) {
        var fileData, size, output;
        if (arg === '-') {
          process.stdin.on('data', function(buf) {
            fileData += buf.toString();
          });
          process.stdin.on('end', function() {
            process.stdin.pause();
            output = JSON.parse(fileData);
            console.log(JSON.stringify(output));
          });
          fileData = '';
          process.stdin.resume();
        }
        else if (fs.existsSync(arg)) {
          fileData = fs.readFileSync(arg, "binary");
          output = JSON.parse(fileData);
          console.log(JSON.stringify(output));
        }
        else {
          console.log("unexpected arg or file not found: " + arg);
        }
      });
    }
    catch (exc1) {
      console.log("Exception:" + exc1);
      //console.log("Exception:" + JSON.stringify(exc1, null, 2));
    }
}

main(process.argv.slice(2));

