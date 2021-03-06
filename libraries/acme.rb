#
# Author:: Thijs Houtenbos <thoutenbos@schubergphilis.com>
# Cookbook:: letsencrypt
# Library:: acme
#
# Copyright 2015 Schuberg Philis
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

begin
  require 'acme-client'
rescue LoadError => e
  Chef::Log.warn("Acme library dependency 'acme-client' not loaded: #{e}")
end

def acme_client
  Chef::Application.fatal!('Acme requires that a contact is specified') if node['letsencrypt']['contact'].size == 0
  return @client if @client

  if node['letsencrypt']['private_key'].nil?
    private_key = OpenSSL::PKey::RSA.new(2048)
  else
    private_key = OpenSSL::PKey::RSA.new(node['letsencrypt']['private_key'])
  end

  @client = Acme::Client.new(private_key: private_key, endpoint: node['letsencrypt']['endpoint'])

  if node['letsencrypt']['private_key'].nil?
    registration = acme_client.register(contact: node['letsencrypt']['contact'])
    registration.agree_terms
    node.set['letsencrypt']['private_key'] = private_key.to_pem
  end

  @client
end

def acme_authz(domain)
  acme_client.authorize(domain: domain)
end

def acme_validate(authz)
  authz.request_verification

  sleep 10
  times = 0

  while times <= 6
    break unless authz.verify_status == 'pending'
    times += 1
    sleep 10
  end

  authz
end

def acme_validate_immediately(authz, method, tokenroot, auth_file)
  tokenroot.run_action(:create)
  auth_file.run_action(:create)
  validate = authz.send(method.to_sym)
  validate.request_verification

  sleep 10
  times = 0

  while times <= 6
    break unless validate.verify_status == 'pending'
    times += 1
    sleep 10
  end

  validate
end

def acme_cert(cn, key, alt_names = [])
  csr = Acme::Client::CertificateRequest.new(
    common_name: cn,
    names: [cn, alt_names].flatten.compact,
    private_key: key
  )

  acme_client.new_certificate(csr)
end

def self_signed_cert(cn, key)
  cert = OpenSSL::X509::Certificate.new
  cert.subject = cert.issuer = OpenSSL::X509::Name.new([
    ['CN', cn, OpenSSL::ASN1::UTF8STRING]
  ])
  cert.not_before = Time.now
  cert.not_after = Time.now + 60 * 60 * 24 * node['letsencrypt']['renew']
  cert.public_key = key.public_key
  cert.serial = 0x0
  cert.version = 2

  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = cert
  ef.issuer_certificate = cert
  cert.extensions = [
    ef.create_extension('basicConstraints', 'CA:FALSE', true),
    ef.create_extension('subjectKeyIdentifier', 'hash'),
  ]

  cert.sign key, OpenSSL::Digest::SHA256.new
end
