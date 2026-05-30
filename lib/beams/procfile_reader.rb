# frozen_string_literal: true

module Beams
  class ProcfileReader
    def self.parse(content)
      content.each_line.with_object({}) do |line, hash|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        name, command = line.split(":", 2)
        hash[name.strip] = command.strip if name && command
      end
    end
  end
end
