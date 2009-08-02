# saunalahti-sms – Send SMS messages using oma.saunalahti.fi
# Copyright © 2009 Johan Kiviniemi
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

require 'fileutils'
require 'logger'
require 'mechanize'
require 'net/netrc'

class SaunalahtiSMS < WWW::Mechanize
  class Error < RuntimeError; end

  class Status < Struct.new :left, :sent; end

  CACHE_DIR    = ::File.expand_path '~/.cache/saunalahti_sms'
  COOKIES_FILE = ::File.join CACHE_DIR, 'cookies'

  SMS_URI = 'https://oma.saunalahti.fi/settings/smsSend'

  def initialize
    super()
    @html_parser = WWW::Mechanize.html_parser  # XXX Bug workaround

    self.log = Logger.new $stderr
    self.log.level = Logger::INFO

    FileUtils.mkdir_p CACHE_DIR

    load_cookies
  end

  def status
    get_and_login SMS_URI

    text = page.search('form[action=smsSend] .tdcontent1').first.inner_text

    num_sent    = nil
    num_monthly = nil
    num_paid    = nil

    m = text.match /Lähetettyjä viestejä: ([0-9]+)/
    num_sent = m[1].to_i if m

    m = text.match /Kuukausittaisia viestejä jäljellä: ([0-9]+)/
    num_monthly = m[1].to_i if m

    m = text.match /Kertakäyttöisiä viestejä jäljellä: ([0-9]+)/
    num_paid = m[1].to_i if m

    if num_sent.nil? or num_monthly.nil? or num_paid.nil?
      raise Error, "Failed to parse status"
    end

    Status.new num_monthly+num_paid, num_sent
  end

  def send_sms recipients, message
    if recipients.empty?
      raise ArgumentError, "No recipients given", caller
    end

    if recipients.find do |r| r !~ /\A[0-9]+\z/ end
      raise ArgumentError, "Invalid recipient format", caller
    end

    unless (1..160) === message.length
      raise ArgumentError, "Message length must be 1..160", caller
    end

    if status.left < 1
      raise Error, "No messages left"
    end

    get_and_login SMS_URI

    form = page.forms.find do |f| f.name == 'myform' end
    raise Error, "Failed to find the SMS form" unless form

    form['recipients'] = recipients.join(',')
    form['text'] = message

    log.info "Sending SMS"

    form.click_button

    errors = page.search('.error').inner_text
    if errors != 'Viesti lähetetty.'
      raise Error, "Send failed: #{errors}"
    end

    nil
  end

  def get_and_login uri
    if not page or page.uri.to_s != uri.to_s
      get uri
    end

    login_if_needed
  end

  def login_if_needed
    form = page.forms.find do |f| f.name == 'login_form' end
    if form
      rc = Net::Netrc.locate('oma.saunalahti.fi') or
           raise Error, '.netrc missing or no entry found'

      form['username'] = rc.login
      form['password'] = rc.password

      log.info "Logging in"

      form.click_button
    end

    form = page.forms.find do |f| f.name == 'login_form' end
    raise Error, "Login failed" if form
  end

  def get *args
    sleep 1+5*rand

    super
    page.parser.encoding = 'ISO-8859-1'  # XXX Bug workaround

    save_cookies
  end

  def load_cookies
    begin
      @cookie_jar.load COOKIES_FILE
    rescue Errno::ENOENT
      # Ignore.
    end
  end

  def save_cookies
    @cookie_jar.save_as COOKIES_FILE
  end
end

