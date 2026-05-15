___TERMS_OF_SERVICE___

By creating or modifying this file you agree to Google Tag Manager's Community
Template Gallery Developer Terms of Service available at
https://developers.google.com/tag-manager/gallery-tos (or such other URL as
Google may provide), as modified from time to time.


___INFO___

{
  "type": "TAG",
  "id": "cvt_tapperai",
  "version": 1,
  "displayName": "Tapper Ad Fraud Protection",
  "categories": ["ADVERTISING", "ANALYTICS", "REMARKETING"],
  "description": "Monitors ad traffic and protects your campaigns from invalid clicks and ad fraud. Requires a Tapper account — get your Public Key at tapper.ai.",
  "brand": {
    "id": "github.com_tapperai",
    "displayName": "Tapper"
  },
  "containerContexts": ["WEB"],
  "securityGroups": []
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "publicKey",
    "displayName": "Public Key",
    "simpleValueType": true,
    "notSetText": "Enter your Tapper Public Key (pk_live_...)",
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      },
      {
        "type": "REGEX",
        "args": ["^pk_(live|test)_"],
        "errorMessage": "Must start with pk_live_ or pk_test_"
      }
    ],
    "help": "Find your Public Key in the Tapper dashboard under Settings."
  }
]


___SANDBOXED_JS_FOR_WEB_TEMPLATE___

var injectScript = require('injectScript');
var callInWindow = require('callInWindow');

injectScript(
  'https://monitor.tapper.ai/bundle.js',
  function() {
    callInWindow('tapper.init', data.publicKey);
    data.gtmOnSuccess();
  },
  data.gtmOnFailure,
  'tapper-bundle'
);


___PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "inject_script",
        "versionId": "1"
      },
      "param": [
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://monitor.tapper.ai/"
              }
            ]
          }
        }
      ]
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_globals",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keys",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {"type": 1, "string": "key"},
                  {"type": 1, "string": "read"},
                  {"type": 1, "string": "write"},
                  {"type": 1, "string": "execute"}
                ],
                "mapValue": [
                  {"type": 1, "string": "tapper"},
                  {"type": 8, "boolean": true},
                  {"type": 8, "boolean": false},
                  {"type": 8, "boolean": true}
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {"type": 1, "string": "key"},
                  {"type": 1, "string": "read"},
                  {"type": 1, "string": "write"},
                  {"type": 1, "string": "execute"}
                ],
                "mapValue": [
                  {"type": 1, "string": "tapper.init"},
                  {"type": 8, "boolean": true},
                  {"type": 8, "boolean": false},
                  {"type": 8, "boolean": true}
                ]
              }
            ]
          }
        }
      ]
    },
    "isRequired": true
  }
]
