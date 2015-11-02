#!/usr/bin/env ruby

def gen_redirect(f,suffix)
    info = f.split('/')
    link_name = '/' + info[1].downcase + '-' + suffix
    target = '/downloads/' + f
    "Redirect #{link_name} #{target}\n"
end

BASE_DIR = '/var/local/testing-packages'
PACKAGES_DIR = File.join BASE_DIR, "downloads"
VALID_DISTROS = %w(Ubuntu Debian openSUSE CentOS)

Dir.chdir(PACKAGES_DIR)

htaccess = ""

DISTROS = Dir['*/*'].map do |d|
    distro = d.split('/')[1]

    # If the distro starts with a VALID_DISTRO string
    if !VALID_DISTROS.map{|vd| distro.match(/^#{vd}/)}.compact.empty?
        distro
    else
        nil
    end
end.compact.sort.uniq

htaccess = ""
DISTROS.each do |distro|
    packages = Dir["*/#{distro}"]
    packages_ce  = packages.reject{|f| f =~ /pro/}.sort
    packages_pro = packages.reject{|f| f !~ /pro/}.sort

    if p_ce = packages_ce.sort[-1]
        Dir["#{p_ce}/*"].each do |p|
            if p =~ /(amd64|x86_64)\.(rpm|deb)$/
                htaccess << gen_redirect(p, 'latest')
            end
        end
    end

    if p_pro = packages_pro.sort[-1]
        Dir["#{p_ce}/*"].each do |p|
            if p =~ /(amd64|x86_64)\.(rpm|deb)$/
                htaccess << gen_redirect(p, 'pro-latest')
            end
        end
    end
end

puts htaccess

File.open((File.join BASE_DIR, '.htaccess'), "w") do |f|
    f.write htaccess
end
