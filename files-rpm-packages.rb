#!/usr/bin/env ruby

# Usage: ./files-rpm-packages.rb -d templates/centos6/centos6.spec.tpl -f <DESTDIR_INSTALL_PATH> -g

$: << File.dirname(__FILE__)

require 'optparse'
require 'ostruct'
require 'find'
require 'pp'
require 'fileutils'

MACRO_DICT = {
    "%{_sysconfdir}"     => "/etc",
    "%{_bindir}"         => "/usr/bin",
    "%{_sbindir}"        => "/usr/sbin",
    "%{_mandir}"         => "/usr/share/man",
    "%{_javadir}"        => "/usr/share/java",
    "%{_datadir}"        => "/usr/share",
    "%{_tmppath}"        => "/var/tmp",
    "%{_sharedstatedir}" => "/var/lib",
    "%{_datarootdir}"    => "/usr/share",
    "%{_localstatedir}"  => "/var",
    "%{_unitdir}"        => "/lib/systemd/system"
}

# if __FILE__ == $0
#     keys = MACRO_DICT.collect{|k,v|k}.join(" ")
#     puts "for macro in #{keys};do"
#     puts "echo \"\\\"$macro\\\" => \\\"$(rpm --eval $macro)\\\"\","
#     puts "done"
# end

TIMESTAMP = Time.now.strftime("%Y%m%d%H%M")

VALID_DIRECTIVES = /^\s*(%files|%config|%{|\/)/

SECTIONS = %w(
                %build
                %changelog
                %clean
                %description
                %files
                %install
                %package
                %post
                %prep?
                %setup
            )

SECTIONS_REGEXP = Regexp.new("^(#{SECTIONS.join('|')})(?:(?: )(.*)$)?")

# Monkey-patch to add colours
class String
    def red;   colorize(31); end
    def green; colorize(32); end
    def blue;  colorize(34); end

    def colorize(color_code); "\e[#{color_code}m#{self}\e[0m"; end
end

def banner(str)
    puts
    puts str.blue
end

class Pkgfiles < Array
    attr_accessor :files

    def initialize(files)
        files.each do |file|
            self << Pkgfile.new(file)
        end
    end

    def match(regex)
        m = self.select do |f|
            f.match(regex)
        end

        !m.empty?
    end

    def filenames(opts,&block)
        pkgs = self.select(&block)

        if opts.glob
            filenames = pkgs.collect do |f|
                # count the entries starting with this path:
                count_files = pkgs.count{|e| e.dir == f.dir}

                # files in dir
                dir_path = opts.dir.split('/')[0..(-opts.keep-1)].join('/')
                dir_path = File.join(dir_path,f.dir,"*")

                files_in_dir = Dir[dir_path].count

                if files_in_dir == count_files
                    f.dir + "/*"
                else
                    f.filename
                end
            end.uniq
        else
            filenames = pkgs.collect{|f| f.filename}
        end

        filenames
    end
end

class Pkgfile
    attr_accessor :filename, :occurrences

    def initialize(filename)
        @filename    = filename
        @occurrences = 0
    end

    def match(regex)
        if regex.match(@filename)
            @occurrences += 1
            true
        else
            false
        end
    end

    def dir
        File.dirname(@filename)
    end
end

opts = OpenStruct.new
OptionParser.new do |o|
    o.on("-d RPM")          {|e| opts.rpm    = e}
    o.on("-f FILES")        {|e| opts.dir    = e}
    o.on("-p PREFIX")       {|e| opts.prefix = e}
    o.on("-k KEEPNUM")      {|e| opts.keep   = e}
    o.on("-g")              {|e| opts.glob   = e}
end.parse!

# starting from right to left of the DIR option, keep this number of elements
opts.keep ||= "0"
opts.keep = opts.keep.to_i.abs

opts.prefix ||= "/"

# leading path to be removed
opts.rm_start = opts.dir.split('/')[0..(-1-opts.keep)].join('/')

files = Array.new
Find.find(opts.dir).each do |file|
    # skip directories
    next if File.directory? file

    # remove the leading path
    file = file[(opts.rm_start.length + 1)..-1]

    # prepend the prefix
    file = File.join(opts.prefix,file) if opts.prefix

    # store the file
    files << file
end

pkgfiles = Pkgfiles.new(files)

current_package = nil

File.open(opts.rpm).each do |line|
    line.strip!

    if (m = line.match(SECTIONS_REGEXP))
        section, arg = m.to_a[1..-1]
        if section == "%files"
            arg ||= "opennebula"
            current_package = arg

            banner current_package
        else
            current_package = nil
        end
        next
    end

    next unless current_package
    next unless line =~ VALID_DIRECTIVES

    file = line.split[-1]
    MACRO_DICT.each{|k,v| file[k]=v if file.include? k}


    if file.match(/\*$/)
        file_regex = Regexp.new("^" + file.gsub("*",".*") + "$")
    else
        if File.directory?(File.join(opts.dir,file))
            file_regex = Regexp.new("^" + file + "(/.*|$)")
        else
            file_regex = Regexp.new("^" + file + "$")
        end
    end
    if !pkgfiles.match(file_regex)
        puts "\t#{file}"
    end
end

banner "unclassified"

unclassified = pkgfiles.filenames(opts){|e| e.occurrences == 0}
unclassified.each {|f| puts "\t#{f}" }

banner "duplicated"

duplicated = pkgfiles.filenames(opts){|e| e.occurrences > 1}
duplicated.each {|f| puts "\t#{f}" }
