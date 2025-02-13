# -*- coding:binary -*-

require 'spec_helper'
require 'rex/text'

RSpec.describe Msf::Serializer::ReadableText do
  # The described_class API takes a mix of strings and whitespace character counts
  let(:indent_string) { '' }
  let(:indent_length) { indent_string.length }

  let(:default_module_options) do
    [
      Msf::Opt::RHOSTS,
      Msf::Opt::RPORT(3000),
      Msf::OptString.new(
        'foo',
        [true, 'Foo option', 'bar']
      ),
      Msf::OptString.new(
        'fizz',
        [true, 'fizz option', 'buzz']
      ),
      Msf::OptString.new(
        'baz',
        [true, 'baz option', 'qux']
      ),
      Msf::OptString.new(
        'OptionWithModuleDefault',
        [true, 'option with module default', true]
      ),
      Msf::OptFloat.new('FloatValue', [false, 'A FloatValue ', 3.5]),
      Msf::OptString.new(
        'NewOptionName',
        [true, 'An option with a new name. Aliases ensure the old and new names are synchronized', 'default_value'],
        aliases: ['OLD_OPTION_NAME']
      ),
      Msf::OptString.new(
        'SMBUser',
        [true, 'The SMB username'],
        fallbacks: ['username']
      ),
      Msf::OptString.new(
        'SMBDomain',
        [true, 'The SMB username', 'WORKGROUP'],
        aliases: ['WindowsDomain'],
        fallbacks: ['domain']
      )
    ]
  end

  let(:default_advanced_module_options) do
    [
      Msf::OptEnum.new('DigestAlgorithm', [ true, 'The digest algorithm to use', 'SHA256', %w[SHA1 SHA256] ])
    ]
  end

  let(:module_options) { default_module_options }
  let(:advanced_module_options) { default_advanced_module_options }

  # (see Msf::Exploit::Remote::Kerberos::ServiceAuthenticator::Options#kerberos_auth_options)
  def kerberos_auth_options(protocol:, auth_methods:)
    mixin = Class.new.extend(Msf::Exploit::Remote::Kerberos::ServiceAuthenticator::Options)
    mixin.kerberos_auth_options(protocol: protocol, auth_methods: auth_methods)
  end

  let(:aux_mod) do
    mod_klass = Class.new(Msf::Auxiliary) do
      def initialize
        super(
          'Name' => 'mock module',
          'Description' => 'mock module',
          'Author' => ['Unknown'],
          'License' => MSF_LICENSE,
          'DefaultOptions' => {
            'OptionWithModuleDefault' => false,
            'foo' => 'foo_from_module',
            'baz' => 'baz_from_module'
          },
        )
      end
    end

    mod = mod_klass.new
    mod.send(:register_options, module_options)
    mod.send(:register_advanced_options, advanced_module_options)
    mock_framework = instance_double(::Msf::Framework, datastore: Msf::DataStore.new)
    allow(mod).to receive(:framework).and_return(mock_framework)
    mod
  end

  let(:aux_mod_with_set_options) do
    mod = aux_mod.replicant
    mod.framework.datastore['RHOSTS'] = '192.0.2.2'
    mod.framework.datastore['FloatValue'] = 5
    mod.framework.datastore['foo'] = 'foo_from_framework'
    mod.datastore['foo'] = 'new_value'
    mod.datastore.unset('foo')
    mod.datastore['OLD_OPTION_NAME'] = nil
    mod.datastore['username'] = 'username'
    mod.datastore['fizz'] = 'new_fizz'
    mod
  end

  before(:each) do
    allow(Rex::Text::Table).to receive(:wrapped_tables?).and_return(true)
  end

  describe '.dump_datastore', if: ENV['DATASTORE_FALLBACKS'] do
    context 'when the datastore is empty' do
      it 'returns the datastore as a table' do
        expect(described_class.dump_datastore('Table name', Msf::DataStore.new, indent_length)).to match_table <<~TABLE
          Table name
          ==========

          No entries in data store.
        TABLE
      end
    end

    context 'when the datastore has values' do
      it 'returns the datastore as a table' do
        expect(described_class.dump_datastore('Table name', aux_mod_with_set_options.datastore, indent_length)).to match_table <<~TABLE
          Table name
          ==========

          Name                     Value
          ----                     -----
          DigestAlgorithm          SHA256
          FloatValue               5
          NewOptionName
          OptionWithModuleDefault  false
          RHOSTS                   192.0.2.2
          RPORT                    3000
          SMBDomain                WORKGROUP
          SMBUser                  username
          VERBOSE                  false
          WORKSPACE
          baz                      baz_from_module
          fizz                     new_fizz
          foo                      foo_from_framework
          username                 username
        TABLE
      end
    end
  end

  describe '.dump_options', if: ENV['DATASTORE_FALLBACKS'] do
    context 'when missing is false' do
      it 'returns the options as a table' do
        expect(described_class.dump_options(aux_mod_with_set_options, indent_string, false)).to match_table <<~TABLE
          Name                     Current Setting     Required  Description
          ----                     ---------------     --------  -----------
          FloatValue               5                   no        A FloatValue
          NewOptionName                                yes       An option with a new name. Aliases ensure the old and new names are synchronized
          OptionWithModuleDefault  false               yes       option with module default
          RHOSTS                   192.0.2.2           yes       The target host(s), see https://github.com/rapid7/metasploit-framework/wiki/Using-Metasploit
          RPORT                    3000                yes       The target port
          SMBDomain                WORKGROUP           yes       The SMB username
          SMBUser                  username            yes       The SMB username
          baz                      baz_from_module     yes       baz option
          fizz                     new_fizz            yes       fizz option
          foo                      foo_from_framework  yes       Foo option
        TABLE
      end
    end

    context 'when missing is true' do
      it 'returns the options as a table' do
        expect(described_class.dump_options(aux_mod_with_set_options, indent_string, true)).to match_table <<~TABLE
          Name           Current Setting  Required  Description
          ----           ---------------  --------  -----------
          NewOptionName                   yes       An option with a new name. Aliases ensure the old and new names are synchronized
        TABLE
      end
    end
  end

  describe '.dump_advanced_options', if: ENV['DATASTORE_FALLBACKS'] do
    context 'when kerberos options are present' do
      let(:advanced_module_options) do
        [
          *default_advanced_module_options,
          *kerberos_auth_options(protocol: 'Winrm', auth_methods: Msf::Exploit::Remote::AuthOption::WINRM_OPTIONS),
        ]
      end

      it 'returns the options as a table' do
        expect(described_class.dump_advanced_options(aux_mod_with_set_options, indent_string)).to match_table <<~TABLE
          Name             Current Setting  Required  Description
          ----             ---------------  --------  -----------
          DigestAlgorithm  SHA256           yes       The digest algorithm to use (Accepted: SHA1, SHA256)
          VERBOSE          false            no        Enable detailed status messages
          WORKSPACE                         no        Specify the workspace for this module
          Winrm::Auth      auto             yes       The Authentication mechanism to use (Accepted: auto, ntlm, kerberos, plaintext)


          Active when Winrm::Auth is kerberos:

          Name                              Current Setting                                   Required  Description
          ----                              ---------------                                   --------  -----------
          DomainControllerRhost                                                               no        The resolvable rhost for the Domain Controller
          Winrm::Krb5Ccname                                                                   no        The ccache file to use for kerberos authentication
          Winrm::KrbOfferedEncryptionTypes  AES256,AES128,RC4-HMAC,DES-CBC-MD5,DES3-CBC-SHA1  yes       Kerberos encryption types to offer
          Winrm::Rhostname                                                                    no        The rhostname which is required for kerberos - the SPN
        TABLE
      end
    end
  end
end
