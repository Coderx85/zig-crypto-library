const path = require('path');
const load = require('node-gyp-build')(path.resolve(__dirname));

// Snowflake namespace
const Snowflake = {
  Id: load.Id,
  Batch: load.Batch,
};

// Nanoid: callable function with .Batch method
const nanoid = function nanoid(length) {
  return load.nanoid(length);
};
nanoid.Batch = function Batch(count, length) {
  return load.nanoidBatch(count, length);
};

module.exports = { Snowflake, nanoid };
