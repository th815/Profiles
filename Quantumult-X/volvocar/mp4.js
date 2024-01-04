/**
 * @fileoverview Rewrite script to replace 'imgUrl' in JSON response with an empty string.
 *
 * @supported Quantumult X (v1.0.5-build173)
 */

// $response.body contains the body of the HTTP response.
// We assume it is in JSON format.

var body = $response.body;
var obj = JSON.parse(body);

// Replace 'imgUrl' with an empty string
if (obj && obj.data && obj.data.imgUrl) {
    obj.data.imgUrl = '';
}

// Convert the object back to a JSON string
body = JSON.stringify(obj);

// Output the modified body to the console for debugging
console.log(body);

// End the script and return the modified response body
$done(body);

