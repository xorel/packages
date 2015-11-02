#!/usr/bin/env ruby

require 'find'

def sql_insert(link_name, desc, url)
    sql = "INSERT INTO files VALUES(NULL,1,"
    sql << "'#{link_name}',"
    sql << "'#{desc}',"
    sql << "'#{url}');"
end

files = Dir['downloads/**/*'].select{|f| File.file? f}
files << ARGV[0] if ARGV[0]

files.each do |file|
    next if file =~ /orig/
    next if file !~ /(deb|rpm|tar.gz)$/

    arch = file.match(/[\._](\w+)\.\w+$/)[1]

    case arch
    when "tar"
        version = file.match(/-(.*).tar.gz$/)[1]
        link_name = "tar-opennebula-#{version}.tar.gz"
        desc = "OpenNebula #{version} tarball"
        url = file
    when "src"
        next
    else
        _, v, d, package    = file.split('/')
        version = v.split('-')[1]
        distro, distro_version = d.split('-')
        url = "http://dev.opennebula.org/packages/" + file.split('/')[1..-1].join('/')

        link_name   = "#{d.downcase}-#{package}"
        desc        = "OpenNebula #{version} #{distro} #{distro_version} #{arch}"
    end

    puts sql_insert(link_name, desc, url)
end
