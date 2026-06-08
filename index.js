const path = require('path');
const load = require('node-gyp-build')(path.resolve(__dirname));

const Snowflake = {
  Id: load.Id,
  Batch: load.Batch,
};

module.exports = { Snowflake };
