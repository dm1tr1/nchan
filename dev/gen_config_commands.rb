#!/usr/bin/ruby
ROOT_DIR=".."
SRC_DIR="src"
CONFIG_IN="nchan_commands.rb"
CONFIG_OUT=ARGV[0]
  
class CfCmd #let's make a DSL!
  class OneOf
    def initialize(arg) 
      @arg=arg
    end
    def []=(k,v)
      @arg[k]=v
    end
    def [](val)
      ret=@arg[val]
      raise "Unknown value lookup #{val}" if ret.nil?
      ret
    end
  end
  class Cmd
    attr_accessor :name, :type, :set, :conf, :offset_name
    attr_accessor :contexts, :args, :legacy, :alt, :disabled
    def type_line
      lut=OneOf.new(main: :NGX_HTTP_MAIN_CONF, srv: :NGX_HTTP_SRV_CONF, loc: :NGX_HTTP_LOC_CONF, 'if': :NGX_HTTP_LIF_CONF)
      args_lut= OneOf.new(0 => :NGX_CONF_NOARGS, false => :NGX_CONF_NOARGS)
      
      (1..7).each{|n| args_lut[n]="NGX_CONF_TAKE#{n}"}
      
      tl=[]
      
      contexts.each { |v| tl << lut[v] }
      (Enumerable === args ? args : ([args]) ).each {|arg| tl << args_lut[arg]}
      tl.join "|"
    end
    
    def conf_line
      OneOf.new(loc_conf: :NGX_HTTP_LOC_CONF_OFFSET, main_conf: :NGX_HTTP_MAIN_CONF_OFFSET)[conf]
    end
    def offset_line
      tpdf=OneOf.new(main_conf: :nchan_main_conf_t, loc_conf: :nchan_loc_conf_t)
      if offset_name
        "offsetof(#{tpdf[conf]}, #{offset_name})"
      else
        0
      end
    end
    def initialize(name, func)
      self.name=name
      self.set=func
    end
    def conf_offset(val)

    end
    
    def to_c_def(altname=nil, comment=nil)
      str= <<-END.gsub(/^ {6}/, '')
        { ngx_string("#{altname || name}"),#{comment && " //#{comment}"}
          #{type_line},
          #{set},
          #{conf_line},
          #{offset_line},
          NULL } ,
      END
    end
    def to_s
      str=[]
      str << to_c_def
      if self.legacy
        lgc = self.legacy.kind_of?(Array) ? self.legacy : [ self.legacy ]
        lgc.each do |v|
          str << to_c_def(v, "legacy for #{name}")
        end
      end
      (alt || []).each {|v| str << to_c_def(v, "alt for #{name}")}
      if disabled
        str.unshift "/* DISABLED\r\n"
        str.push "  */\r\n"
      end
      str << "\r\n"
      str.join
    end
  end
  def initialize(&block)
    @cmds=[]
    instance_eval &block
  end
  def method_missing(name, *args)
    define_cmd name, *args
  end
  def define_cmd(name, valid_contexts, handler, conf, opt={})
    cmd=Cmd.new name, handler
    cmd.args= opt.has_key?(:args) ? opt[:args] : 1
    cmd.contexts= valid_contexts
    if Array === conf
      cmd.conf=conf[0]
      cmd.offset_name=conf[1]
    else
      cmd.conf=conf
    end
    cmd.legacy=opt[:legacy]
    cmd.alt=opt[:alt]
    cmd.disabled=opt[:disabled]
    @cmds << cmd
  end
  
  def to_s
    str= <<-END.gsub(/^ {6}/, '')
      //AUTOGENERATED, do not edit! see #{CONFIG_IN}
      static ngx_command_t  nchan_commands[] = {
        #{@cmds.join}
        ngx_null_command
      };
    END
  end
end
begin
  cf=eval File.read("#{ROOT_DIR}/#{SRC_DIR}/#{CONFIG_IN}")
rescue Exception => e
  STDERR.puts e.message.gsub(/^\(eval\)/, "#{SRC_DIR}/#{CONFIG_IN}")
  exit 1
end

if CONFIG_OUT
  File.write "#{ROOT_DIR}/#{SRC_DIR}/#{CONFIG_OUT}", cf.to_s
  puts "wrote config commands to #{SRC_DIR}/#{CONFIG_OUT}"
else
  puts cf.to_s
end