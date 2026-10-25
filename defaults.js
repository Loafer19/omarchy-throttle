// Shared by Model.js (QML) and scripts/backend.sh (read as JSON after the
// "var CONFIG = " prefix), so keep this file a single plain JSON object.
var CONFIG = {
  "enabled": true,
  "downMbit": 0,
  "upMbit": 0,
  "apps": {
    "heroic": { "downMbit": 0, "upMbit": 0, "gamesSafe": true, "bulkMiB": 4 },
    "steam": { "downMbit": 0, "upMbit": 0, "gamesSafe": true, "bulkMiB": 4 }
  }
};
