# First of all we add a method to the Regexp class
class Regexp

  # a Regexp has captures when its source has open parenthesis
  # which are preceded by an even number of slashes and followed by
  # a question mark
  def has_captures?
    self.source.match(/(?:^|[^\\])(?:\\\\)*\([^?]/)
  end

  # We may want to remove captures
  def remove_captures
    new = self.source.gsub(/(^|[^\\])((?:\\\\)*)\(([^?])/) {
      "%s%s(?:%s" % [$1, $2, $3]
    }
    Regexp.new(new)
  end
end

module Irc

  # +MessageMapper+ is a class designed to reduce the amount of regexps and
  # string parsing plugins and bot modules need to do, in order to process
  # and respond to messages.
  #
  # You add templates to the MessageMapper which are examined by the handle
  # method when handling a message. The templates tell the mapper which
  # method in its parent class (your class) to invoke for that message. The
  # string is split, optionally defaulted and validated before being passed
  # to the matched method.
  #
  # A template such as "foo :option :otheroption" will match the string "foo
  # bar baz" and, by default, result in method +foo+ being called, if
  # present, in the parent class. It will receive two parameters, the
  # Message (derived from BasicUserMessage) and a Hash containing
  #   {:option => "bar", :otheroption => "baz"}
  # See the #map method for more details.
  class MessageMapper
    # used to set the method name used as a fallback for unmatched messages.
    # The default fallback is a method called "usage".
    attr_writer :fallback

    # parent::   parent class which will receive mapped messages
    #
    # create a new MessageMapper with parent class +parent+. This class will
    # receive messages from the mapper via the handle() method.
    def initialize(parent)
      @parent = parent
      @templates = Array.new
      @fallback = :usage
    end

    # args:: hash format containing arguments for this template
    #
    # map a template string to an action. example:
    #   map 'myplugin :parameter1 :parameter2'
    # (other examples follow). By default, maps a matched string to an
    # action with the name of the first word in the template. The action is
    # a method which takes a message and a parameter hash for arguments.
    #
    # The :action => 'method_name' option can be used to override this
    # default behaviour. Example:
    #   map 'myplugin :parameter1 :parameter2', :action => 'mymethod'
    #
    # By default whether a handler is fired depends on an auth check. The
    # first component of the string is used for the auth check, unless
    # overridden via the :auth => 'auth_name' option.
    #
    # Static parameters (not prefixed with ':' or '*') must match the
    # respective component of the message exactly. Example:
    #   map 'myplugin :foo is :bar'
    # will only match messages of the form "myplugin something is
    # somethingelse"
    #
    # Dynamic parameters can be specified by a colon ':' to match a single
    # component (whitespace seperated), or a * to suck up all following
    # parameters into an array. Example:
    #   map 'myplugin :parameter1 *rest'
    #
    # You can provide defaults for dynamic components using the :defaults
    # parameter. If a component has a default, then it is optional. e.g:
    #   map 'myplugin :foo :bar', :defaults => {:bar => 'qux'}
    # would match 'myplugin param param2' and also 'myplugin param'. In the
    # latter case, :bar would be provided from the default.
    #
    # Components can be validated before being allowed to match, for
    # example if you need a component to be a number:
    #   map 'myplugin :param', :requirements => {:param => /^\d+$/}
    # will only match strings of the form 'myplugin 1234' or some other
    # number.
    #
    # Templates can be set not to match public or private messages using the
    # :public or :private boolean options.
    #
    # Further examples:
    #
    #   # match 'karmastats' and call my stats() method
    #   map 'karmastats', :action => 'stats'
    #   # match 'karma' with an optional 'key' and call my karma() method
    #   map 'karma :key', :defaults => {:key => false}
    #   # match 'karma for something' and call my karma() method
    #   map 'karma for :key'
    #
    #   # two matches, one for public messages in a channel, one for
    #   # private messages which therefore require a channel argument
    #   map 'urls search :channel :limit :string', :action => 'search',
    #             :defaults => {:limit => 4},
    #             :requirements => {:limit => /^\d+$/},
    #             :public => false
    #   plugin.map 'urls search :limit :string', :action => 'search',
    #             :defaults => {:limit => 4},
    #             :requirements => {:limit => /^\d+$/},
    #             :private => false
    #
    def map(botmodule, *args)
      @templates << MessageTemplate.new(botmodule, *args)
    end

    def each
      @templates.each {|tmpl| yield tmpl}
    end

    def last
      @templates.last
    end

    # m::  derived from BasicUserMessage
    #
    # examine the message +m+, comparing it with each map()'d template to
    # find and process a match. Templates are examined in the order they
    # were map()'d - first match wins.
    #
    # returns +true+ if a match is found including fallbacks, +false+
    # otherwise.
    def handle(m)
      return false if @templates.empty?
      failures = []
      @templates.each do |tmpl|
        options, failure = tmpl.recognize(m)
        if options.nil?
          failures << [tmpl, failure]
        else
          action = tmpl.options[:action]
          unless @parent.respond_to?(action)
            failures << [tmpl, "class does not respond to action #{action}"]
            next
          end
          auth = tmpl.options[:full_auth_path]
          debug "checking auth for #{auth}"
          if m.bot.auth.allow?(auth, m.source, m.replyto)
            debug "template match found and auth'd: #{action.inspect} #{options.inspect}"
            @parent.send(action, m, options)
            return true
          end
          debug "auth failed for #{auth}"
          # if it's just an auth failure but otherwise the match is good,
          # don't try any more handlers
          return false
        end
      end
      failures.each {|f, r|
        debug "#{f.inspect} => #{r}"
      }
      debug "no handler found, trying fallback"
      if @fallback && @parent.respond_to?(@fallback)
        if m.bot.auth.allow?(@fallback, m.source, m.replyto)
          @parent.send(@fallback, m, {})
          return true
        end
      end
      return false
    end

  end

  # +MessageParameter+ is a class that collects all the necessary information
  # about a message parameter (the :param or *param that can be found in a
  # #map).
  #
  # It has a +name+ attribute, +multi+ and +optional+ booleans that tell if the
  # parameter collects more than one word, and if it's optional (respectively).
  # In the latter case, it can also have a default value.
  #
  # It is possible to assign a collector to a MessageParameter. This can be either
  # a Regexp with captures or an Array or a Hash. The collector defines what the
  # collect() method is supposed to return.
  class MessageParameter
    attr_reader :name
    attr_writer :multi
    attr_writer :optional
    attr_accessor :default

    def initialize(name)
      self.name = name
      @multi = false
      @optional = false
      @default = nil
      @regexp = nil
      @index = nil
    end

    def name=(val)
      @name = val.to_sym
    end

    def multi?
      @multi
    end

    def optional?
      @optional
    end

    # This method is used to turn a matched item into the actual parameter value.
    # It only does something when collector= set the @regexp to something. In
    # this case, _val_ is matched against @regexp and then the match result
    # specified in @index is selected. As a special case, when @index is nil
    # the first non-nil captured group is returned.
    def collect(val)
      return val unless @regexp
      mdata = @regexp.match(val)
      if @index
        return mdata[@index]
      else
        return mdata[1..-1].compact.first
      end
    end

    # This method allow the plugin programmer to choose to only pick a subset of the
    # string matched by a parameter. This is done by passing the collector=()
    # method either a Regexp with captures or an Array or a Hash.
    #
    # When the method is passed a Regexp with captures, the collect() method will
    # return the first non-nil captured group.
    #
    # When the method is passed an Array, it will grab a regexp from the first
    # element, and possibly an index from the second element. The index can
    # also be nil.
    #
    # When the method is passed a Hash, it will grab a regexp from the :regexp
    # element, and possibly an index from the :index element. The index can
    # also be nil.
    def collector=(val)
      return unless val
      case val
      when Regexp
        return unless val.has_captures?
        @regexp = val
      when Array
        warning "Collector #{val.inspect} is too long, ignoring extra entries" unless val.length <= 2
        @regexp = val[0]
        @index = val[1] rescue nil
      when Hash
        raise "Collector #{val.inspect} doesn't have a :regexp key" unless val.has_key?(:regexp)
        @regexp = val[:regexp]
        @index = val.fetch(:regexp, nil)
      end
      raise "The regexp of collector #{val.inspect} isn't a Regexp" unless @regexp.kind_of?(Regexp)
      raise "The index of collector #{val.inspect} is present but not an integer " if @index and not @index.kind_of?(Fixnum)
    end

    def inspect
      mul = multi? ? " multi" : " single"
      opt = optional? ? " optional" : " needed"
      if @regexp
        reg = " regexp=%s index=%d" % [@regexp, @index]
      else
        reg = nil
      end
      "<#{self.class.to_s}%s%s%s%s>" % [name, mul, opt, reg]
    end
  end

  class MessageTemplate
    attr_reader :defaults # The defaults hash
    attr_reader :options  # The options hash
    attr_reader :template
    attr_reader :items
    attr_reader :regexp

    def initialize(botmodule, template, hash={})
      raise ArgumentError, "Third argument must be a hash!" unless hash.kind_of?(Hash)
      @defaults = hash[:defaults].kind_of?(Hash) ? hash.delete(:defaults) : {}
      @requirements = hash[:requirements].kind_of?(Hash) ? hash.delete(:requirements) : {}
      @template = template

      self.items = template
      # @dyn_items is an array of MessageParameters, except for the first entry
      # which is the template
      @dyn_items = @items.collect { |it|
        if it.kind_of?(Symbol)
          i = it.to_s
          opt = MessageParameter.new(i)
          if i.sub!(/^\*/,"")
            opt.name = i
            opt.multi = true
          end
          opt.default = @defaults[opt.name]
          opt.collector = @requirements[opt.name]
          opt
        else
          nil
        end
      }
      @dyn_items.unshift(template).compact!
      debug "Items: #{@items.inspect}; dyn items: #{@dyn_items.inspect}"

      self.regexp = template
      debug "Command #{template.inspect} in #{botmodule} will match using #{@regexp}"

      set_auth_path(botmodule, hash)

      unless hash.has_key?(:action)
        hash[:action] = items[0]
      end

      @options = hash

      # debug "Create template #{self.inspect}"
    end

    def set_auth_path(botmodule, hash)
      if hash.has_key?(:auth)
        warning "Command #{@template.inspect} in #{botmodule} uses old :auth syntax, please upgrade"
      end
      if hash.has_key?(:full_auth_path)
        warning "Command #{@template.inspect} in #{botmodule} sets :full_auth_path, please don't do this"
      else
        case botmodule
        when String
          pre = botmodule
        when Plugins::BotModule
          pre = botmodule.name
        else
          raise ArgumentError, "Can't find auth base in #{botmodule.inspect}"
        end
        words = items.reject{ |x|
          x == pre || x.kind_of?(Symbol) || x =~ /\[|\]/
        }
        if words.empty?
          post = nil
        else
          post = words.first
        end
        if hash.has_key?(:auth_path)
          extra = hash[:auth_path]
          if extra.sub!(/^:/, "")
            pre += "::" + post
            post = nil
          end
          if extra.sub!(/:$/, "")
            if words.length > 1
              post = [post,words[1]].compact.join("::")
            end
          end
          pre = nil if extra.sub!(/^!/, "")
          post = nil if extra.sub!(/!$/, "")
        else
          extra = nil
        end
        hash[:full_auth_path] = [pre,extra,post].compact.join("::")
        debug "Command #{@template} in #{botmodule} will use authPath #{hash[:full_auth_path]}"
        # TODO check if the full_auth_path is sane
      end
    end

    def items=(str)
      raise ArgumentError, "template #{str.inspect} should be a String" unless str.kind_of?(String)

      # split and convert ':xyz' to symbols
      items = str.strip.split(/\]?\s+\[?|\]?$/).collect { |c|
        # there might be extra (non-alphanumeric) stuff (e.g. punctuation) after the symbol name
        if /^(:|\*)(\w+)(.*)/ =~ c
          sym = ($1 == ':' ) ? $2.intern : "*#{$2}".intern
          if $3.empty?
            sym
          else
            [sym, $3]
          end
        else
          c
        end
      }.flatten
      @items = items

      raise ArgumentError, "Illegal template -- first component cannot be dynamic: #{str.inspect}" if @items.first.kind_of? Symbol

      raise ArgumentError, "Illegal template -- first component cannot be optional: #{str.inspect}" if @items.first =~ /\[|\]/

      # Verify uniqueness of each component.
      @items.inject({}) do |seen, item|
        if item.kind_of? Symbol
          # We must remove the initial * when present,
          # because the parameters hash will intern both :item and *item as :item
          it = item.to_s.sub(/^\*/,"").intern
          raise ArgumentError, "Illegal template -- duplicate item #{it} in #{str.inspect}" if seen.key? it
          seen[it] = true
        end
        seen
      end
    end

    def regexp=(str)
      # debug "Original string: #{str.inspect}"
      rx = Regexp.escape(str)
      # debug "Escaped: #{rx.inspect}"
      rx.gsub!(/((?:\\ )*)(:|\\\*)(\w+)/) { |m|
        whites = $1
        is_single = $2 == ":"
        name = $3.intern

        not_needed = @defaults.has_key?(name)

        has_req = @requirements[name]
        debug "Requirements for #{name}: #{has_req.inspect}"
        case has_req
        when nil
          sub = is_single ? "\\S+" : ".*"
        when Regexp
          # Remove captures and the ^ and $ that are sometimes placed in requirement regexps
          sub = has_req.remove_captures.source.sub(/^\^/,'').sub(/\$$/,'')
        when String
          sub = Regexp.escape(has_req)
        when Array
          sub = has_req[0].remove_captures.source.sub(/^\^/,'').sub(/\$$/,'')
        when Hash
          sub = has_req[:regexp].remove_captures.source.sub(/^\^/,'').sub(/\$$/,'')
        else
          warning "Odd requirement #{has_req.inspect} of class #{has_req.class} for parameter '#{name}'"
          sub = Regexp.escape(has_req.to_s) rescue "\\S+"
        end
        debug "Regexp for #{name}: #{sub.inspect}"
        s = "#{not_needed ? "(?:" : ""}#{whites}(#{sub})#{ not_needed ? ")?" : ""}"
      }
      # debug "Replaced dyns: #{rx.inspect}"
      rx.gsub!(/((?:\\ )*)\\\[/, "(?:\\1")
      rx.gsub!(/\\\]/, ")?")
      # debug "Delimited optionals: #{rx.inspect}"
      rx.gsub!(/(?:\\ )+/, "\\s+")
      # debug "Corrected spaces: #{rx.inspect}"
      @regexp = Regexp.new("^#{rx}$")
    end

    # Recognize the provided string components, returning a hash of
    # recognized values, or [nil, reason] if the string isn't recognized.
    def recognize(m)

      debug "Testing #{m.message.inspect} against #{self.inspect}"

      # Early out
      return nil, "template #{@template} is not configured for private messages" if @options.has_key?(:private) && !@options[:private] && m.private?
      return nil, "template #{@template} is not configured for public messages" if @options.has_key?(:public) && !@options[:public] && !m.private?

      options = {}

      matching = @regexp.match(m.message)
      return nil, "#{m.message.inspect} doesn't match #{@template} (#{@regexp})" unless matching
      return nil, "#{m.message.inspect} only matches #{@template} (#{@regexp}) partially: #{matching[0].inspect}" unless matching[0] == m.message

      debug_match = matching[1..-1].collect{ |d| d.inspect}.join(', ')
      debug "#{m.message.inspect} matched #{@regexp} with #{debug_match}"
      debug "Associating #{debug_match} with dyn items #{@dyn_items.join(', ')}"

      @dyn_items.each_with_index { |it, i|
        next if i == 0
        item = it.name
        debug "dyn item #{item} (multi-word: #{it.multi?.inspect})"
        if it.multi?
          if matching[i].nil?
            default = it.default
            case default
            when Array
              value = default.clone
            when String
              value = default.strip.split
            when nil, false, []
              value = []
            else
              warning "Unmanageable default #{default} detected for :*#{item.to_s}, using []"
              value = []
            end
            case default
            when String
              value.instance_variable_set(:@string_value, default)
            else
              value.instance_variable_set(:@string_value, value.join(' '))
            end
          else
            value = matching[i].split
            value.instance_variable_set(:@string_value, matching[i])
          end
          def value.to_s
            @string_value
          end
        else
          if matching[i].nil?
            warning "No default value for option #{item.inspect} specified" unless @defaults.has_key?(item)
            value = it.default
          else
            value = it.collect(matching[i])
          end
        end
        options[item] = value
        debug "set #{item} to #{options[item].inspect}"
      }

      options.delete_if {|k, v| v.nil?} # Remove nil values.
      return options, nil
    end

    def inspect
      when_str = @requirements.empty? ? "" : " when #{@requirements.inspect}"
      default_str = @defaults.empty? ? "" : " || #{@defaults.inspect}"
      "<#{self.class.to_s} #{@items.map { |c| c.inspect }.join(' ').inspect}#{default_str}#{when_str}>"
    end

    def requirements_for(name)
      name = name.to_s.sub(/^\*/,"").intern if (/^\*/ =~ name.inspect)
      presence = (@defaults.key?(name) && @defaults[name].nil?)
      requirement = case @requirements[name]
        when nil then nil
        when Regexp then "match #{@requirements[name].inspect}"
        else "be equal to #{@requirements[name].inspect}"
      end
      if presence && requirement then "#{name} must be present and #{requirement}"
      elsif presence || requirement then "#{name} must #{requirement || 'be present'}"
      else "#{name} has no requirements"
      end
    end
  end
end
