{ ... }:

{
  env.REPRO_VALUE = "leaf-v1";

  tasks."repro:task-v1" = {
    description = "task from leaf-v1";
    exec = ''
      echo leaf-v1
    '';
  };

  processes."proc-v1".exec = ''
    echo leaf-v1
    sleep infinity
  '';
}
