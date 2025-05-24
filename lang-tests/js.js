// JavaScript standard syntax showcase

/*
    This is a multiline comment.
*/

"use strict";

function Example(value) {
  this.value = value;
  this.array = [];
  for (var i = 0; i<5; i++) {
    this.array.push(i);
  }
  this.obj = { a: 1, b: 2 };
}

const regex = /${h}/g;

Example.prototype.method = function(x) {
  try {
    if (x < 0) throw new Error("Negative");
    return Math.sqrt(x);
  } catch (e) {
    return NaN;
  } finally {
    console.log("Done");
  }
};

function generator(n) {
  var result = [];
  for (var i = 0; i < n; i++) {
    result.push(i * i);
  }
  return result;
}

function asyncFunction(callback) {
  setTimeout(function() {
    callback("done");
  }, 1000);
}

var arrowFunc = function(x) {
  return x + 1;
};

var x = 2;
switch (x) {
  case 1:
  case 2:
    x += 1;
    break;
  default:
    x = 0;
}

var arr = [1, 2, 3];
for (var i = 0; i < arr.length; i++) {
  console.log(arr[i]);
}

var obj = { x: 1, y: 2 };
for (var key in obj) {
  if (obj.hasOwnProperty(key)) {
    console.log(key + ":" + obj[key]);
  }
}

const constant = "This is a constant value.";
let variable = "This is a variable value.";

(function() {
  console.log("IIFE");
})();
