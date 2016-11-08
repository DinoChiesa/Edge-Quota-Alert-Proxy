# Quota Alert Example Proxy

This Edge proxy bundle demonstrates how to generate the appropriate alert emails
when a developer app (==apikey) reaches configurable thresholds.

Today, in Apigee Edge, there is no built-in way to have Edge alert someone (a
developer, an API owner, etc) if and when a Quota is exceeded.  There's no
built-in way to alert someone when the consumption of a particular Quota reaches a
certain threshold.  But some customers want to send out such alerts. This example
shows how.

## The basic idea 

 - each proxy should check for quota thresholds, and make it possible to
   send alerts when configured thresholds are exceeded.
   
 - because the proxies run in a distributed environment, there's a race
   condition, around detecting thresholds and sending emails. (for more on that, see [here](#discontinuity-in-quota-accounting)).  One MP may
   see a threshold exceeded, while another does not. Therefore proxies
   must not send emails directly. Instead they set a flag when a threshold is
   reached. This is an idempotent operation.
 
 - later, on some configured schedule, a separate program can check the
   cache and actually send the emails that need sending.

There are two proxies used to implement this example.
The first is just a regular proxy, which inserts pending alerts into cache when appropriate.
The second is the email-sending proxy, which reads those alerts and acts on them.
Use cron or similar to invoke this second proxy, once per day, or week, or whatever. 


## Running the Sample

You can deploy and run the example right away.  

```
  ./tools/provisionQuotaAlert.sh -o ORGNAME -e ENVNAME -t tools/sample-config.json
  
```

You will see discontinuous changes in the quota level consumed. This is especially
noticeable if you have a 2- DN environment, or if you have more than 2 MPs. This
is normal and expected, because the quota is distributed and not synchronous.

To tear-down the things (app, developer, product, proxy) set up by that script,
you can re-run it with the -r option.

```
  ./tools/provisionQuotaAlert.sh -o ORGNAME -e ENVNAME -r
  
```


## How It Works

In more detail, here's how the first proxy works: 

1. validate the api key or token

2. check the quota based on the client_id

   The quota will do one of 2 things. It will either pass, or fail.  The failure
   indicates "over quota", and immediately returns a 500 error (or whatever,
   based on fault rules) to the caller.

3. IF the quota passes, then, retrieve the threshold configuration information
   from KVM or some other store, like custom attributes on the dev, app, or
   product. If using any of the internal Edge stores, then retrieval will benefit
   from the implicit cache.
   
   This configuration information will include a set of one or more of the following:
   
   * threshold number (percentage), 
   * email subject and message template
   * addresses: to, from, cc

   So, you might configure a message to be sent when 65% is reached, and a different
   message at 85%, and another at 99%.  

4. JS step: compute the usage %, and compare it against the configured thresholds.

   Set a context variable indicating the highest threshold exceeded.
   "highest_threshold_reached"

5. If `highest_threshold_reached` is non-null, this indicates that at least one
   of the configured thresholds has been exceeded. Therefore, check to see if
   THIS threshold has a pending alert.  
   
   read cache entry, using key:
      `concat(prefix="alert-pending", client_id, highest_threshold_reached)` 

   The result will be either null or non-null. The former indicates that no alert
   for this threshold is pending. The latter indicates the alert for the given
   threshold is already pending.
   
6. If null, we want to set the flag to indicate that an alert needs to be
   sent. This is done by writing the Edge cache entry.  Before doing that, we need to
   compute the value of the thing that gets written to cache.  This is done via a JS step, "prepAlerts.js".

   This computes the usage %, and compare it against the configured thresholds.

7. Finally, PopulateCache with the prepared value. 

   * key: `concat(prefix="alert-pending", client_id, threshold_reached)`  
   * value: JSON payload with various computed values, necessary for sending an email later.
   * TTL: determined by how often the email sending job will run.  If
     the email sending check happens once per day at 10pm, then this cache
     ought to expire at ... say... midnight, after the job has been run.
      

## The Email Sending (Alert processing) Proxy

Asynchronously, a cron job will invoke a "send alerts" proxy periodically; for example, once each day at 
10pm. The cron job will retrieve all client_ids, and post then
to a URL.

This example relies on a "check" proxy to do the checking. The proxy will:

1. Verify the API key, to Retrieve the API Product name. 

2. In Nodejs:

   for each {client_id, threshold}, check the cache for "alert-pending".

   Send the response back with the pending alerts.


One could imagine modifying that nodejs to actually send emails. 


To use this, you must create an API Product and set a custom attribute, named
'quota_alerts_info', with the appropriate threshold alert information.

The configuration looks like this:

```json
[{
  "threshold": 65,
  "message": "Dear {developer.firstname} {developer.lastname}, on {system.time}, your app, {developer.app.name}, reached {quota_usage_pct}% of the alotted quota. Sincerely, The Mgmt.",
  "subject": "API usage alert for {developer.app.name}",
  "sendto": "{developer.email}",
  "from": "DChiesa@apigee.com"
}, {
  "threshold": 85,
  "message": "Dear {developer.firstname} {developer.lastname}, on {system.time}, your app, {developer.app.name}, reached {quota_usage_pct}% of the alotted quota. You really should look into this.",
  "subject": "API usage alert for {developer.app.name}",
  "sendto": "{developer.email}",
  "from": "DChiesa@apigee.com"
}, {
  "threshold": 95,
  "message": "Dear {developer.firstname} {developer.lastname}, on {system.time}, your app, {developer.app.name}, reached {quota_usage_pct}% of the alotted quota. THE END IS NEAR!",
  "subject": "API usage alert for {developer.app.name}",
  "sendto": "{developer.email}",
  "cc" : "Dino@apigee.com",
  "from": "DChiesa@apigee.com"
}]
```

Each item in the array is an object with a "threshold" property which is an
integer, and a set of other string properties, which can have any name. The
pattern above is a good one to follow for email alerts. If you have a different
alerting system, you may want different string properties.

This configuration must be escaped and stored as a single string. 

To demonstrate this, you must have a service callout call an API that
sends an email. I have used mandrill.com for the purposes of
demonstration. It can be any system, even a webhook into a nodejs app
that uses smtp, if you like. You could also configure it to send other
types of alerts, like SMS or post to a hipchat/slack chatroom.

## Producing the Threshold Config

You can use the [`gen-compact-form.js`](./tools/gen-compact-form.js) to generate
the compact form of the JSON for the quota alerts. 

To use it, write a text file with the json you want, then invoke the script and
pass that file. The script just reads the JSON then serializes it with minimal
spacing.

Example:

```
    tools/gen-compact-form.js my-threshold-config.json
    
```

## Discontinuity in Quota Accounting

In Apigee Edge, there will be multiple distributed processes enforcing a quota. In
most cases, the synchronization between these processes is periodic, and out of
band with respect to the requests being processed.

In more detail, let's call each process that enforces a quota a Message Processor,
and suppose there are two, MP1 and MP2. Now, let's suppose there is a
load-distributor in front of those MPs such that in general they share an equal
proportion of the load, 50/50.  But, for a small sample of requests (~100), there
may be an unequal distribution of load, say 60/40 or even more unbalanced. Also, one MP
may receive 7 requests in a row, while the other MP receives the next 3.

The result is that any one MP will in general have an out-of-date view of the
state of the quota consumption. Periodically the MPs synchronize and reconcile
their counts, and this happens transparently from the point of view of the API
proxy developer. But it still occurs. As a result, one can see the phenomenon of
discontinous quota counts. To illustrate, this is data taken from an actual series
of single-threaded requests:

```
Request 1 - served by MP 1
  quota consumed: 32
  quota remaining: 48

Request 2 - served by MP 2
  quota consumed: 40
  quota remaining: 40

Request 3 - served by MP 2
  quota consumed: 43
  quota remaining: 37
  
Request 4 - served by MP 1
  quota consumed: 43
  quota remaining: 37
```

With this discontinuity, it is not possible to use a simple "equals" test within
an MP to see if a quota threshold has been breached. In the above example, the
consumed count will never have been viewed as being 42, in any MP, at any point.
It jumps from 32 to 43 in one MP, and from 40 to 43 in the other. At higher
concurrency and with more MPs, the problem is exacerbated.

A greater-than-or-equals test is necessary, keeping in mind that this test will
evaluate to true in multiple MPs for each threshold. Therefore the email cannot be
sent out synchronously with respect to the request being handled.

Instead, the better approach is to have each MP set a flag indicating that a
threshold has been breached. Unlike sending an email, setting the flag is an
idempotent operation - it does not matter how many times the flag is set. Then,
later, a check can run, to examine which thresholds have been breached, and can
then send the notifications out.



## Remaining To do: 

* Actually send emails.  This should be not too difficult using a nodejs smtp module.
* Modify to emit webhooks (eg, slack notification)
