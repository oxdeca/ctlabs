#!/usr/bin/env ruby
# -----------------------------------------------------------------------------
# File        : ctlabs/test_automation_profiles.rb
# Description : Unit test for Automation.load_profiles duplicate key detection
# -----------------------------------------------------------------------------

require 'tempfile'
require_relative 'lib/automation'

class MockLog
  attr_reader :warnings, :debugs

  def initialize
    @warnings = []
    @debugs   = []
  end

  def write(msg, level = 'info')
    case level.to_s
    when 'warn'
      @warnings << msg
    when 'debug'
      @debugs << msg
    end
  end
end

failed = 0

def assert(desc, condition)
  if condition
    puts "  [PASS] #{desc}"
  else
    puts "  [FAIL] #{desc}"
    caller.each { |c| puts "         #{c}" }
    false
  end
end

puts "== Testing Automation.load_profiles Duplicate Key Warnings =="

# 1. Test duplicate ad: keys under profiles
log = MockLog.new
fixture_dup = Tempfile.new(['setup_profiles_dup', '.yml'])
fixture_dup.write(<<~YAML)
vars:
  domain: ctlabs.internal
profiles:
  ad:
    realm: FIRST.CTLABS.INTERNAL
    netbios: FIRST
  ca:
    cert_name: root-ca
  ad:
    realm: SECOND.CTLABS.INTERNAL
    netbios: SECOND
YAML
fixture_dup.close

res = Automation.load_profiles(fixture_dup.path, log: log)

assert("Returns parsed Hash", res.is_a?(Hash))
assert("Last duplicate definition wins (SECOND)", res.dig('profiles', 'ad', 'realm') == 'SECOND.CTLABS.INTERNAL')
assert("Emitted exactly 1 warning", log.warnings.size == 1)
warn_msg = log.warnings.first || ""
assert("Warning mentions file path", warn_msg.include?(fixture_dup.path))
assert("Warning mentions dotted key path 'profiles.ad'", warn_msg.include?('profiles.ad'))
assert("Warning identifies duplicate line 9", warn_msg.include?('line 9'))
assert("Warning identifies first line 4", warn_msg.include?('first defined at line 4'))
assert("Emitted debug log for loaded profile", log.debugs.any? { |d| d.include?('loaded profile mapping') })

fixture_dup.unlink

# 2. Test merge keys (<<) are not flagged as duplicates
log_merge = MockLog.new
fixture_merge = Tempfile.new(['setup_profiles_merge', '.yml'])
fixture_merge.write(<<~YAML)
_defaults: &defaults
  role: common
profiles:
  p1:
    <<: *defaults
    name: p1
  p2:
    <<: *defaults
    name: p2
YAML
fixture_merge.close

res_merge = Automation.load_profiles(fixture_merge.path, log: log_merge)
assert("Merge keys are not flagged as duplicates (0 warnings)", log_merge.warnings.empty?)
assert("p1 has inherited role", res_merge.dig('profiles', 'p1', 'role') == 'common')
assert("p2 has inherited role", res_merge.dig('profiles', 'p2', 'role') == 'common')

fixture_merge.unlink

# 3. Test clean profile without duplicates
log_clean = MockLog.new
fixture_clean = Tempfile.new(['setup_profiles_clean', '.yml'])
fixture_clean.write(<<~YAML)
profiles:
  dns:
    zone: ctlabs.internal
  web:
    port: 80
YAML
fixture_clean.close

res_clean = Automation.load_profiles(fixture_clean.path, log: log_clean)
assert("Clean profile produces 0 warnings", log_clean.warnings.empty?)
assert("Parsed correctly", res_clean.dig('profiles', 'dns', 'zone') == 'ctlabs.internal')

fixture_clean.unlink

# 4. Test missing file returns empty hash
log_missing = MockLog.new
res_missing = Automation.load_profiles('/nonexistent/path/profiles.yml', log: log_missing)
assert("Missing file returns empty hash", res_missing == {})
assert("Missing file produces 0 warnings", log_missing.warnings.empty?)

puts "\nAll tests completed!"
