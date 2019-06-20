#!/usr/bin/env ruby


# Usage: ./files-deb-packages.rb -d templates/ubuntu14.04-debian -f <DESTDIR_INSTALL_PATH> -g

require 'optparse'
require 'ostruct'
require 'find'
require 'pp'
require 'fileutils'

TIMESTAMP = Time.now.strftime("%Y%m%d%H%M")

# Backs-up a file
#
# @param file [String] Name of the file to back up.
def file_bk(file)
    FileUtils.cp(file, "#{file}_#{TIMESTAMP}")
end

def banner(str)
    puts
    puts str.blue
end

# Monkey-patch to add colours
class String
    def red;   colorize(31); end
    def green; colorize(32); end
    def blue;  colorize(34); end

    def colorize(color_code); "\e[#{color_code}m#{self}\e[0m"; end
end

class Pkgfiles < Array
    attr_accessor :files

    def initialize(files)
        files.each do |file|
            self << Pkgfile.new(file)
        end
    end

    # def each
    #     @files.each do |file|
    #         yield file
    #     end
    # end

    # def select
    #     @files.select do |file|
    #         yield file
    #     end
    # end

    def match(regex,basename,file,dest)
        m = self.select do |f|
            f.match(regex,basename,file,dest)
        end

        !m.empty?
    end
end

class Pkgfile
    attr_accessor :filename, :occurrences

    def initialize(filename)
        @filename = filename
        @occurrences = {}
    end

    def match(regex,basename,file,dest)
        if regex.match(@filename)
            @occurrences[basename] = [] if @occurrences[basename].nil?
            @occurrences[basename] << [file,dest,regex]
            true
        else
            false
        end
    end

    def n_occurrences
        return 0 if @occurrences.empty?
        @occurrences.values.collect{|e| e.length}.inject{|sum,x| sum + x }
    end

    def dir
        File.dirname(@filename)
    end
end

opts = OpenStruct.new
OptionParser.new do |o|
    o.on("-d DEBIAN")       {|e| opts.debian = e}
    o.on("-f FILES")        {|e| opts.dir    = e}
    o.on("-p PREFIX")       {|e| opts.prefix = e}
    o.on("-k KEEPNUM")      {|e| opts.keep   = e}
    o.on("-g")              {|e| opts.glob   = e}
end.parse!

# starting from right to left of the DIR option, keep this number of elements
opts.keep ||= "1"
opts.keep = opts.keep.to_i.abs

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

debian_files = Dir[opts.debian + '/*install']
if debian_files.empty?
    STDERR.puts "no debian *install files found"
    exit 1
end

debian_files.each do |f_install|
    basename = File.basename(f_install)
    banner basename

    File.readlines(f_install).each do |line|
        next if line =~ /^\s*(#|$)/

        file,dest  = line.split

        if file.include?("*")
            file_regex = Regexp.new("^" + file.gsub("*","[^\/]*"))
        else
            file_regex = Regexp.new("^" + file + "$")
        end

        if !pkgfiles.match(file_regex,basename,file,dest)
            puts "\t#{file}".red
        end
    end
end

banner "duplicated"
pkgfiles_dup = pkgfiles.select{|e| e.n_occurrences > 1}
pkgfiles_dup.each do |p|
    puts
    puts p.filename
    p.occurrences.each do |k,v|
        pkg = k.gsub(/\.install$/,"")
        puts "  #{pkg}:"
        v.each do |e|
            puts "    - #{e}"
        end
    end
end

banner "unclassified"

pkgfiles = pkgfiles.select{|e| e.n_occurrences == 0}

pkgfiles = if opts.glob
    pkgfiles.collect do |f|
        # count the entries starting with this path:
        count_files = pkgfiles.count{|e| e.dir == f.dir}

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
    pkgfiles.collect{|f| "\t#{f.filename}"}
end

pkgfiles.each {|f| puts "\t#{f}".green }
