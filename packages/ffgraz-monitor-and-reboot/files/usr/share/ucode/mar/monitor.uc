function timePassed (base, howMuch) {
  return base <= time() - howMuch;
}

function ServiceMonitor(name, config, isRunning, storage, poll) {
  let state = isRunning ? 'running' : 'dead';
  let deadSince = isRunning ? storage.get(name)[0] || time() : null;
  let revives = isRunning ? 0 : storage.get(name).length;
  let maxRevives = 3;

  const tryReviveAfter = 'downtime_until_restart' in config
    ? config.downtime_until_restart : 10;

  function tryRecover() {
    const commands = config.restart ?? [`service ${name} restart`];
    printf('Fixing %J:\n', name);

    for (let i = 0; i < commands.length; i++) {
      printf(' + %s\n', commands[i]);
      system(commands[i]);
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
          // service is unfixable, prepare for reboot
          break;
        }
        if (timePassed(deadSince, tryReviveAfter)) {
          // poll again to be really sure
          isRunning = poll();
          if (isRunning) {
            machine();
            break;
          }

          tryRecover();
          storage.append(name);
          revives++;
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
