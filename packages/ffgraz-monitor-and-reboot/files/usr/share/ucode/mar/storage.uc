const uci = require('uci').cursor();

function err(e, i) {
  if (e && (e !== 'Entry not found' || !i)) {
    printf('ERROR: %J\n', e);
    die(e);
  }
}

function Storage() {
  // in uci we have a list that is named $key and that contains several timestamps

  function get(key, maxAge) {
    let list = split(',', uci.get('ffgraz-monitor-and-reboot', 'state', key) ?? '');
    err(uci.error(), true);

    list = filter(list, str => !!str);
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
      err(uci.error());

      uci.save('ffgraz-monitor-and-reboot');
      err(uci.error());

      uci.commit('ffgraz-monitor-and-reboot');
      err(uci.error());
    },
    clear: (key) => {
      uci.delete('ffgraz-monitor-and-reboot', 'state', key);
      err(uci.error());

      uci.save('ffgraz-monitor-and-reboot');
      err(uci.error());

      uci.commit('ffgraz-monitor-and-reboot');
      err(uci.error());
    }
  };
}

export default Storage;
