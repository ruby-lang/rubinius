# depends on: module.rb

class NilClass
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal::TYPE_NIL
  end
end

class TrueClass
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal::TYPE_TRUE
  end
end

class FalseClass
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal::TYPE_FALSE
  end
end

class Class
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal::TYPE_CLASS +
    Marshal.serialize_integer(self.name.length) + self.name
  end
end

class Module
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal::TYPE_MODULE +
    Marshal.serialize_integer(self.name.length) + self.name
  end
end

class Symbol
  def to_marshal(depth = -1, subclass = nil, links = {})
    str = self.to_s
    Marshal::TYPE_SYMBOL +
    Marshal.serialize_integer(str.length) + str
  end
end

class String
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal.serialize_instance_variables_prefix(self) +
    Marshal.serialize_extended_object(self) +
    Marshal.serialize_user_class(self, depth, subclass) +
    Marshal::TYPE_STRING +
    Marshal.serialize_integer(self.length) + self +
    Marshal.serialize_instance_variables_suffix(self, depth, subclass, links)
  end
end

class Integer
  def to_marshal(depth = -1, subclass = nil, links = {})
    if Marshal.fixnum? self
      to_marshal_fixnum
    else
      to_marshal_bignum
    end
  end

  def to_marshal_fixnum
    Marshal::TYPE_FIXNUM +
    Marshal.serialize_integer(self)
  end

  def to_marshal_bignum
    str = Marshal::TYPE_BIGNUM +
          (self < 0 ? '-' : '+') + "\0"
    size_index = str.length - 1
    cnt = 0
    num = self.abs
    while num != 0
      str << Marshal.to_byte(num & 0xFF)
      num >>= 8
      cnt += 1
    end
    if cnt % 2 == 1
      str << "\0"
      cnt += 1
    end
    # TODO - handle bignum of more than 242 bytes
    str[size_index] = Marshal.to_byte(((cnt - 4) / 2) + 7)
    str
  end
end

class Regexp
  def to_marshal(depth = -1, subclass = nil, links = {})
    str = self.source
    Marshal.serialize_instance_variables_prefix(self) +
    Marshal.serialize_extended_object(self) +
    Marshal.serialize_user_class(self, depth, subclass) +
    Marshal::TYPE_REGEXP +
    Marshal.serialize_integer(str.length) + str +
    Marshal.to_byte(self.options & 0x7) +
    Marshal.serialize_instance_variables_suffix(self, depth, subclass, links)
  end
end

class Struct
  def to_marshal(depth = -1, subclass = nil, links = {})
    str = Marshal.serialize_extended_object(self) +
          Marshal::TYPE_STRUCT +
          self.class.name.to_sym.to_marshal +
          Marshal.serialize_integer(self.length)
    self.each_pair do |sym, val|
      str << sym.to_marshal +
             Marshal.serialize_duplicate(val, depth, subclass, links)
    end
    str
  end
end

class Array
  def to_marshal(depth = -1, subclass = nil, links = {})
    str = Marshal.serialize_instance_variables_prefix(self) +
          Marshal.serialize_extended_object(self) +
          Marshal.serialize_user_class(self, depth, subclass) +
          Marshal::TYPE_ARRAY +
          Marshal.serialize_integer(self.length)
    self.each do |element|
      str << Marshal.serialize_duplicate(element, depth, subclass, links)
    end
    str + Marshal.serialize_instance_variables_suffix(self, depth, subclass, links)
  end
end

class Hash
  def to_marshal(depth = -1, subclass = nil, links = {})
    str = Marshal.serialize_instance_variables_prefix(self) +
          Marshal.serialize_extended_object(self) +
          Marshal.serialize_user_class(self, depth, subclass) +
          (self.default ? Marshal::TYPE_HASH_DEF : Marshal::TYPE_HASH) +
          Marshal.serialize_integer(self.length)
    self.each_pair do |(key, val)|
      str << key.to_marshal(depth, subclass, links) +
             Marshal.serialize_duplicate(val, depth, subclass, links)
    end
    str + (self.default ? self.default.to_marshal(depth, subclass, links) : '') +
    Marshal.serialize_instance_variables_suffix(self, depth, subclass, links)
  end
end

class Object
  def to_marshal(depth = -1, subclass = nil, links = {})
    Marshal.serialize_extended_object(self) +
    Marshal::TYPE_OBJECT +
    self.class.name.to_sym.to_marshal +
    Marshal.serialize_instance_variables_suffix(self, depth, subclass, links)
  end
end

module Marshal

  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  VERSION_STRING = "\x04\x08"

  TYPE_NIL = '0'
  TYPE_TRUE = 'T'
  TYPE_FALSE = 'F'
  TYPE_FIXNUM = 'i'

  TYPE_EXTENDED = 'e'
  TYPE_UCLASS = 'C'
  TYPE_OBJECT = 'o'
  TYPE_DATA = 'd'  # no specs
  TYPE_USERDEF = 'u'
  TYPE_USRMARSHAL = 'U'  # no specs
  TYPE_FLOAT = 'f'
  TYPE_BIGNUM = 'l'
  TYPE_STRING = '"'
  TYPE_REGEXP = '/'
  TYPE_ARRAY = '['
  TYPE_HASH = '{'
  TYPE_HASH_DEF = '}'
  TYPE_STRUCT = 'S'
  TYPE_MODULE_OLD = 'M'  # no specs
  TYPE_CLASS = 'c'
  TYPE_MODULE = 'm'

  TYPE_SYMBOL = ':'
  TYPE_SYMLINK = ';'

  TYPE_IVAR = 'I'
  TYPE_LINK = '@'

  def self.dump(obj, depth = -1, io = nil)
    VERSION_STRING + serialize(obj, depth)
  end

  def self.serialize(obj, depth)
    cls = obj.class
    sup = get_superclass(cls)
    [cls, sup].each do |classy|
      if [String, Regexp, Array, Hash].include? classy
        if obj.class != classy
          return obj.to_marshal(depth, obj.class)
        end
      end
    end
    obj.to_marshal(depth)
  end

  def self.serialize_integer(n)
    if n == 0
      s = to_byte(n)
    elsif n > 0 and n < 123
      s = to_byte(n + 5)
    elsif n < 0 and n > -124
      s = to_byte(256 + (n - 5))
    else
      s = "\x00"
      cnt = 0
      4.times do
        s << to_byte(n & 0xFF)
        n >>= 8
        cnt += 1
        break if n == 0 or n == -1
      end
      s[0] = to_byte(n < 0 ? 256 - cnt : cnt)
    end
    s
  end

  def self.serialize_instance_variables_prefix(obj)
    if obj.instance_variables.length > 0
      TYPE_IVAR
    else
      ''
    end
  end

  def self.serialize_instance_variables_suffix(obj, depth = -1, subclass = nil, links = {})
    if obj.class == Object or obj.instance_variables.length > 0
      str = serialize_integer(obj.instance_variables.length)
      obj.instance_variables.each do |ivar|
        sym = ivar.to_sym
        val = obj.instance_variable_get(sym)
        str << sym.to_marshal +
               Marshal.serialize_duplicate(val, depth, subclass, links)
      end
      str
    else
      ''
    end
  end

  def self.serialize_extended_object(obj)
    str = ''
    get_module_names(obj).each do |mod_name|
      str << TYPE_EXTENDED + mod_name.to_sym.to_marshal
    end
    str
  end

  def self.serialize_user_class(obj, depth, subclass)
    if obj.class == subclass
      TYPE_UCLASS + obj.class.name.to_sym.to_marshal
    else
      ''
    end
  end

  def self.serialize_duplicate(obj, depth, subclass, links)
    dup_id = links[obj.object_id]
    if dup_id
      if obj.class == Symbol
        str = TYPE_SYMLINK + serialize_integer(dup_id)
      else
        str = TYPE_LINK + serialize_integer(dup_id)
      end
    else
      if linkable_duplicate? obj
        links[obj.object_id] = (obj.class == Symbol ? links.length : links.length.succ)
      end
      str = obj.to_marshal(depth, subclass, links)
    end
    str
  end

  def self.linkable_duplicate?(obj)
    if fixnum?(obj) or [NilClass, TrueClass, FalseClass].include? obj.class
      false
    else
      true
    end
  end

  def self.fixnum?(n)
    if n.kind_of?(Integer) and n >= -2**30 and n <= (2**30 - 1)
      true
    else
      false
    end
  end

  def self.get_superclass(cls)
    sup = cls.superclass
    while sup and sup.superclass and sup.superclass != Object
      sup = sup.superclass
    end
    sup
  end

  def self.get_module_names(obj)
    names = []
    sup = obj.metaclass.superclass
    while sup and [Module, IncludedModule].include? sup.class
      names << sup.name
      sup = sup.superclass
    end
    names
  end

  def self.to_byte(n)
    [n].pack('C')
  end
end
