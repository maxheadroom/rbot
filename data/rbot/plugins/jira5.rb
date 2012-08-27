#-- vim:sw=2:et
#++
#
# :title: JIRA5 Client Plugin for rbot
#
# Author:: Falko Zurell <falko.zurell@gmail.com>
# Copyright:: (C) 2012 Falko Zurell
# License:: GPL v2
#
# performance simple actions on JIRA issue
# requires a JIRA 5.x instance with REST API
#
# TODO
# 


class Jira5Plugin < Plugin
  Config.register Config::StringValue.new('jira5.url',
     :default => 'host',
     :desc => _('URL end point of the JIRA5 Server API'))
  Config.register Config::StringValue.new('jira5.username',
        :default => 'jirarbot',
        :desc => _('Username the rbot should authenticate to JIRA with'))
  Config.register Config::StringValue.new('jira5.password',
        :default => 'jirarbot',
        :desc => _('Password the rbot should authenticate to JIRA with'))
     

  def help(plugin, topic="")
    
    case topic
      when 'comment'
        _('define <phrase> [from <database>] => Show definition of a phrase')
      when 'create'
        _('match <phrase> [using <strategy>] [from <database>] => Show phrases matching the given pattern')
      when 'resolve'
        _('dictclient databases => List databases; dictclient strategies => List strategies')
      when 'assign'
        _('assign <issue-key> <username> => assigns the issue to the user')
      when 'tome'
        _('tome <issuekey> => assigns the issue to myself (given my irc username matches a valid JIRA account)')
      else
        _('supported commands are: comment, create, resolve, assign, tome')
    end
    
  end

  def host_path
    @bot.config["jira5.url"]
  end

  def initialize
    super
  end

  def privmsg(m)
    unless(m.params =~ /^(\w|-|\.)+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    m.reply Utils.safe_exec(host_path, m.params)
  end
end
plugin = HostPlugin.new
plugin.register("host")
