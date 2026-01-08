{
  services.pueue = {
    enable = true;
    settings = {
      daemon = {
        default_parallel_tasks = 4;
      };
      shared = {
        host = "127.0.0.1";
        port = 6924;
      };
    };
  };
}
