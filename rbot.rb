#!/usr/bin/env ruby

# Copyright (C) 2002 Tom Gilbert.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies of the Software and its documentation and acknowledgment shall be
# given in the documentation and software packages that this Software was
# used.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

$VERBOSE=true

require 'getoptlong'
require 'rbot/ircbot'

$debug = true
$version="0.9.7"
$opts = Hash.new

# print +message+ if debugging is enabled
def debug(message=nil)
  print "DEBUG: #{message}\n" if($debug && message)
  #yield
end

opts = GetoptLong.new(
  [ "--debug", "-d", GetoptLong::NO_ARGUMENT ],
  [ "--help",  "-h", GetoptLong::OPTIONAL_ARGUMENT ]
)

opts.each {|opt, arg|
  $debug = true if(opt == "--debug")
  $opts[opt.sub(/^-+/, "")] = arg
}

botclass = ARGV.shift
botclass = "rbotconf" unless(botclass);

if(bot = Irc::IrcBot.new(botclass))
  if($opts["help"])
    puts bot.help($opts["help"])
  else
    # run the bot
    bot.mainloop
  end
end

