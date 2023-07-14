const uci = require('uci').cursor();

function Storage() {
  // in uci we have a list that is named $key and that contains several timestamps

  function get(key, maxAge) {
    let list = split(',', uci.get('ffgraz-monitor-and-reboot', 'state', key) ?? '');

    if (!list) return [];

    list = map(list, p => int(p));

    if (maxAge) {
      const oldest = time() - maxAge;
      list = filter(list, (ts) => ts > oldest);
    }

    return list;
  }

  return {
    get,
    append: (key) => {
      const list = get(key);
      push(list, time());
      uci.set('ffgraz-monitor-and-reboot', 'state', key, join(',', list));
      uci.save('ffgraz-monitor-and-reboot');
      uci.commit();
    },
    clear: (key) => {
      uci.delete('ffgraz-monitor-and-reboot', 'state', key);
      uci.save('ffgraz-monitor-and-reboot');
      uci.commit();
    }
  };
}

export default Storage;
