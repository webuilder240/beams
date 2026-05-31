# frozen_string_literal: true

require "open3"

module Beams
  module Once
    # Beams::Once::Updater performs the ONCE auto-update on the host.
    #
    # It pulls the latest image, compares the digest of the image the running
    # container was created from against the digest of the freshly-pulled
    # image, and only recreates the container when they differ. The container
    # is recreated with the exact same `docker run` arguments the installer
    # (deploy/once/install.sh) uses, so persistent data on the `beams_storage`
    # volume and the host env file are preserved.
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

      attr_reader :image, :container, :volume, :env_file

      # @param runner [#call] receives a command array, returns stdout String.
      # @param image [String] image reference to pull/run.
      # @param container [String] container name.
      # @param volume [String] named volume for /rails/storage.
      # @param env_file [String] host env file passed via --env-file.
      def initialize(runner: method(:default_run),
                     image: IMAGE,
                     container: CONTAINER,
                     volume: VOLUME,
                     env_file: ENV_FILE)
        @runner = runner
        @image = image
        @container = container
        @volume = volume
        @env_file = env_file
      end

      # Pull the latest image and recreate the container only when the digest
      # changed.
      #
      # @return [Hash] { updated:, current:, latest: }
      def update!
        run(pull_command)

        current = current_image_digest
        latest = latest_image_digest

        return { updated: false, current: current, latest: latest } if current == latest

        run(stop_command)
        run(rm_command)
        run(run_command)

        { updated: true, current: current, latest: latest }
      end

      private

      # Digest (image id) the running container was created from.
      def current_image_digest
        run(inspect_command("{{.Image}}", @container)).strip
      end

      # Digest (image id) of the freshly-pulled image.
      def latest_image_digest
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
