const uci = require('uci').cursor();

function Storage() {
  // in uci we have a list that is named $key and that contains several timestamps

  function get(key, maxAge) {
    let list = uci.get('ffgraz-monitor-and-reboot', 'state', key);

    if (!list) return [];

    list = list.map(p => parseInt(p, 10));

    if (maxAge) {
      oldest = time() - maxAge;
      list = list.filter((ts) => ts > oldest);
    }

    return list;
  }

  return {
    get,
    append: (key) => {
      const list = get(key);
      push(list, time());
      uci.set('ffgraz-monitor-and-reboot', 'state', key, list);
      uci.save('ffgraz-monitor-and-reboot');
      uci.commit();
    },
    clear: (key) => {
      uci.delete(key);
    }
  };
}

export default Storage;
