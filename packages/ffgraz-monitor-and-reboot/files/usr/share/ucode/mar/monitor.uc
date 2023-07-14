function timePassed (base, howMuch) {
  return base <= time() - howMuch;
}

const MAX_GRACE = 60 * 60;

function ServiceMonitor(name, config, isRunning, storage, poll) {
  let state = isRunning ? 'running' : 'dead';
  let deadSince = isRunning ? storage.get(name, MAX_GRACE)[0] || time() : null;
  let revives = isRunning ? 0 : length(storage.get(name, MAX_GRACE));
  let maxRevives = config.attempts_until_reboot ?? 5;

  const tryReviveAfter = 'downtime_until_restart' in config
    ? config.downtime_until_restart : 10;

  function tryRecover() {
    const commands = config.restart ?? [`service ${name} restart`];
    printf('Fixing %J: %s/%s\n', name, revives, maxRevives);

    for (let i = 0; i < length(commands); i++) {
      printf(' + %s\n', commands[i]);
      system(commands[i], 10 * 1000);
    }
  }

  function machine(newIsRunning) {
    // we're getting new running state
    if (newIsRunning === true || newIsRunning === false) {
      isRunning = newIsRunning;
    }

    // printf('State machine %s %s %J\n', name, state, isRunning);

    switch (state) {
      case 'running': {
        if (!isRunning) {
          state = 'dead';
          deadSince = time();
          printf('%s is no longer running\n', name);
        }
        break;
      }
      case 'dead': {
        if (isRunning) {
          // we're no longer dead
          printf('%s is running again\n', name);
          state = 'running';
          revives = 0;
          deadSince = null;
          storage.clear(name);
          break;
        }
        if (revives >= maxRevives) {
          if (!config.disable_reboot) {
            // service is unfixable, prepare for reboot
            const reboots = storage.get('REBOOT', 24 * 60 * 60);
            if (length(reboots) < 3) {
              storage.append('REBOOT');
              printf('Rebooting...\n');
              system('sleep 3s');
              system('reboot');
            }
            break;
          }

          printf('%s is currently broken and could not be repaired\n', name);
          break;
        }
        if (timePassed(deadSince, tryReviveAfter)) {
          // poll again to be really sure
          isRunning = poll();
          if (isRunning) {
            machine();
            break;
          }

          revives++;
          storage.append(name);
          tryRecover();
          // queue another revieve if necesarry
          deadSince = time();
          // wait a bit
          system('sleep 2s');
          // check if we're back
          machine(poll());
          break;
        }
      }
    }
  }

  return {
    machine
  }
}

export default ServiceMonitor;
