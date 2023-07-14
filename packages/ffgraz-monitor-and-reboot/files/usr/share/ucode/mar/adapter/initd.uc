function AdapterInitd() {
  function isRunning(name) {
    // 0=success
    return !system(`service ${name} running`)
  }

  return {
    isRunning
  };
}

export default AdapterInitd;
