#!/usr/bin/env ruby
require 'spec_helper'
require 'puppet/util/windows'

describe Puppet::Util::Windows::SID::Principal, :if => Puppet.features.microsoft_windows? do

  let (:system_bytes) { [1, 1, 0, 0, 0, 0, 0, 5, 18, 0, 0, 0] }
  let (:administrator_bytes) { [1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0, 0] }

  describe ".lookup_account_name" do
    it "should create an instance from a well-known account name" do
      principal = Puppet::Util::Windows::SID::Principal.lookup_account_name('SYSTEM')
      expect(principal.account).to eq('SYSTEM')
      expect(principal.sid_bytes).to eq(system_bytes)
      expect(principal.sid).to eq('S-1-5-18')
      expect(principal.domain).to eq('NT AUTHORITY')
      expect(principal.domain_account).to eq('NT AUTHORITY\\SYSTEM')
      expect(principal.account_type).to eq(:SidTypeWellKnownGroup)
    end

    it "should create an instance from a well-known account prefixed with NT AUTHORITY" do
      principal = Puppet::Util::Windows::SID::Principal.lookup_account_name('NT AUTHORITY\\SYSTEM')
      expect(principal.account).to eq('SYSTEM')
      expect(principal.sid_bytes).to eq(system_bytes)
      expect(principal.sid).to eq('S-1-5-18')
      expect(principal.domain).to eq('NT AUTHORITY')
      expect(principal.domain_account).to eq('NT AUTHORITY\\SYSTEM')
      expect(principal.account_type).to eq(:SidTypeWellKnownGroup)
    end

    it "should create an instance from a local account prefixed with hostname" do
      current_user_name = Puppet::Util::Windows::ADSI::User.current_user_name
      running_as_system = (current_user_name == 'SYSTEM')
      username = running_as_system ? 'Administrator' : current_user_name

      user_exists = Puppet::Util::Windows::ADSI::User.exists?(".\\#{username}")

      # when running as SYSTEM (in Jenkins CI), then Administrator should be used
      # otherwise running in AppVeyor there is no Administrator and a the current local user can be used
      skip if (running_as_system && !user_exists)

      hostname = Socket.gethostname

      principal = Puppet::Util::Windows::SID::Principal.lookup_account_name("#{hostname}\\#{username}")
      expect(principal.account).to match(/^#{Regexp.quote(username)}$/i)
      # skip SID and bytes in this case since the most interesting thing here is domain_account
      expect(principal.domain).to match(/^#{Regexp.quote(hostname)}$/i)
      expect(principal.domain_account).to match(/^#{Regexp.quote(hostname)}\\#{Regexp.quote(username)}$/i)
      expect(principal.account_type).to eq(:SidTypeUser)
    end

    it "should create an instance from a well-known group alias" do
      principal = Puppet::Util::Windows::SID::Principal.lookup_account_name('Administrators')
      expect(principal.account).to eq('Administrators')
      expect(principal.sid_bytes).to eq(administrator_bytes)
      expect(principal.sid).to eq('S-1-5-32-544')
      expect(principal.domain).to eq('BUILTIN')
      expect(principal.domain_account).to eq('BUILTIN\\Administrators')
      expect(principal.account_type).to eq(:SidTypeAlias)
    end

    it "should raise an error when trying to lookup an account that doesn't exist" do
      principal = Puppet::Util::Windows::SID::Principal
      expect {
        principal.lookup_account_name('ConanTheBarbarian')
      }.to raise_error(Puppet::Util::Windows::Error, /Failed to call LookupAccountNameW/)
    end
  end

  describe ".lookup_account_sid" do
    it "should create an instance from a well-known account SID" do
      principal = Puppet::Util::Windows::SID::Principal.lookup_account_sid(system_bytes)
      expect(principal.account).to eq('SYSTEM')
      expect(principal.sid_bytes).to eq(system_bytes)
      expect(principal.sid).to eq('S-1-5-18')
      expect(principal.domain).to eq('NT AUTHORITY')
      expect(principal.domain_account).to eq('NT AUTHORITY\\SYSTEM')

      # Windows API LookupAccountSid behaves differently if current user is SYSTEM
      # even though LookupAccountName does not demonstrate same behavior
      if Puppet::Util::Windows::ADSI::User.current_user_name != 'SYSTEM'
        account_type = :SidTypeWellKnownGroup
      else
        account_type = :SidTypeUser
      end

      expect(principal.account_type).to eq(account_type)
    end

    it "should create an instance from a well-known group SID" do
      principal = Puppet::Util::Windows::SID::Principal.lookup_account_sid(administrator_bytes)
      expect(principal.account).to eq('Administrators')
      expect(principal.sid_bytes).to eq(administrator_bytes)
      expect(principal.sid).to eq('S-1-5-32-544')
      expect(principal.domain).to eq('BUILTIN')
      expect(principal.domain_account).to eq('BUILTIN\\Administrators')
      expect(principal.account_type).to eq(:SidTypeAlias)
    end

    it "should raise an error when trying to lookup completely invalid SID bytes" do
      principal = Puppet::Util::Windows::SID::Principal
      expect {
        principal.lookup_account_sid([])
      }.to raise_error(Puppet::Util::Windows::Error, /Failed to call LookupAccountSidW:  The parameter is incorrect/)
    end

    it "should raise an error when trying to lookup a valid SID that doesn't have a matching account" do
      principal = Puppet::Util::Windows::SID::Principal
      expect {
        # S-1-1-1 which is not a valid account
        principal.lookup_account_sid([1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0])
      }.to raise_error(Puppet::Util::Windows::Error, /Failed to call LookupAccountSidW:  No mapping between account names and security IDs was done/)
    end
  end
end
