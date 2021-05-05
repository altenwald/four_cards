# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Distillery.Releases.Config,
    # This sets the default release built by `mix distillery.release`
    default_release: :default,
    # This sets the default environment used by `mix distillery.release`
    default_environment: Mix.env()

# For a full list of config options for both releases
# and environments, visit https://hexdocs.pm/distillery/config/distillery.html


# You may define one or more environments in this file,
# an environment's settings will override those of a release
# when building in that environment, this combination of release
# and environment configuration is called a profile

environment :dev do
  # If you are running Phoenix, you should make sure that
  # server: true is set and the code reloader is disabled,
  # even in dev mode.
  # It is recommended that you build with MIX_ENV=prod and pass
  # the --env flag to Distillery explicitly if you want to use
  # dev mode.
  set dev_mode: true
  set include_erts: false
  set cookie: :"A8F3A_SVxcqCzB>Yd;&HiF=K2MI]iN2Ec}CXMHMvM^V60RZJe[r24bFxh4ujv3l7"
end

environment :prod do
  set include_erts: true
  set include_src: false
  set cookie: :":yaBz*rxQrPd!oL(v~yB=Wv*nNggRuYVDa)>jq/(7Lg=rapwd?V8U.kr48tJp:1`"
  set vm_args: "rel/vm.args"
  set commands: [
    observer: "rel/commands/observer.sh"
  ]
end

# You may define one or more releases in this file.
# If you have not set a default release, or selected one
# when running `mix distillery.release`, the first release in the file
# will be used by default

release :four_cards do
  set version: Mix.Project.config[:version]
  set applications: [
    :observer_cli,
    :runtime_tools,
    four_cards_console: :permanent,
    four_cards_game: :permanent,
    four_cards_web: :permanent
  ]
end
