# frozen_string_literal: true

require "open3"

module Beams
  module Once
    # Beams::Once::Updater performs the ONCE auto-update on the host.
    #
    # It pulls the configured image, compares the local image ID the running
    # container was created from against the local image ID of the
    # freshly-pulled image, and only recreates the container when they differ
    # (i.e. the same tag now resolves to a new image). The container is
    # recreated with the exact same `docker run` arguments the installer
    # (deploy/once/install.sh) uses, so persistent data on the `beams_storage`
    # volume and the host env file are preserved.
    #
    # The image defaults to ENV["IMAGE"] (written to /etc/beams/beams.env by the
    # installer) and falls back to the IMAGE constant, so a rollback performed by
    # re-running install.sh with IMAGE=<old tag> is respected by the timer and is
    # not undone by re-pulling :latest.
    #
    # This class is Rails-independent and depends only on stdlib so it can run
    # under the host's system ruby (no bundler / no config/environment). Shell
    # execution is injected via a `runner` for testability.
    class Updater
      # Shared constants — MUST stay in sync with deploy/once/install.sh.
      IMAGE     = "ghcr.io/REPLACE_ME/beams:latest"
      CONTAINER = "beams"
      VOLUME    = "beams_storage"
      MOUNT     = "/rails/storage"
      ENV_FILE  = "/etc/beams/beams.env"
      HTTP_PORT  = "80:80"
      HTTPS_PORT = "443:443"
      RESTART_POLICY = "unless-stopped"

      # @param runner [#call] receives a command array, returns stdout String.
      # @param image [String] image reference to pull/run. Defaults to
      #   ENV["IMAGE"] (set via --env-file by install.sh), then the IMAGE
      #   constant, so rollbacks pinning an older tag are respected.
      # @param container [String] container name.
      # @param volume [String] named volume for /rails/storage.
      # @param env_file [String] host env file passed via --env-file.
      def initialize(runner: method(:default_run),
                     image: ENV.fetch("IMAGE", IMAGE),
                     container: CONTAINER,
                     volume: VOLUME,
                     env_file: ENV_FILE)
        @runner = runner
        @image = image
        @container = container
        @volume = volume
        @env_file = env_file
      end

      # Pull the configured image and recreate the container only when the local
      # image ID changed (same tag now resolves to a new image).
      #
      # @return [Hash] { updated:, current:, latest: }
      def update!
        run(pull_command)

        current = current_image_id
        latest = latest_image_id

        return { updated: false, current: current, latest: latest } if current == latest

        run(stop_command)
        run(rm_command)
        run(run_command)

        { updated: true, current: current, latest: latest }
      end

      private

      # Local image ID the running container was created from.
      def current_image_id
        run(inspect_command("{{.Image}}", @container)).strip
      end

      # Local image ID of the freshly-pulled image.
      def latest_image_id
        run(inspect_command("{{.Id}}", @image)).strip
      end

      def pull_command
        [ "docker", "pull", @image ]
      end

      def inspect_command(format, target)
        [ "docker", "inspect", "--format", format, target ]
      end

      def stop_command
        [ "docker", "stop", @container ]
      end

      def rm_command
        [ "docker", "rm", @container ]
      end

      # Same run arguments as deploy/once/install.sh.
      def run_command
        [
          "docker", "run", "-d",
          "--name", @container,
          "--restart", RESTART_POLICY,
          "-p", HTTP_PORT,
          "-p", HTTPS_PORT,
          "-v", "#{@volume}:#{MOUNT}",
          "--env-file", @env_file,
          @image
        ]
      end

      def run(command)
        @runner.call(command)
      end

      # Default runner: execute the command and return stdout, raising on
      # failure. Injected away in tests.
      def default_run(command)
        stdout, status = Open3.capture2(*command)
        raise "command failed (#{status.exitstatus}): #{command.join(' ')}" unless status.success?

        stdout
      end
    end
  end
end
