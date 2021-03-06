## Post-Installation Tasks

### Configure and test sSMTP
Assuming your WordPress jail is named `wordpress`, use a terminal to enter the jail `iocage console wordpress`.  

Edit the file `/usr/local/etc/ssmtp/ssmtp.conf`:

`cd /usr/local/etc/ssmtp && ee ssmtp.conf`

Enter your configuration details in the `ssmtp.conf` file. Modify this example to fit your situation:
```
MailHub=mail.example.com:465     # Mail server to connect to (port 465 is SMTP/SSL)
UseTLS=YES                       # Enable SSL/TLS 
AuthUser=john                    # Username for SMTP AUTH
AuthPass=Secret1                 # Password for SMTP AUTH 
FromLineOverride=YES             # Force the From: address to the user account 
Hostname=myhost.example.com      # Name of this host 
RewriteDomain=myhost.example.com # Where the mail will seem to come from 
Root=postmaster                  # Mail for root@ is redirected to postmaster@
```
Create a txt file `ee test.txt` with the following text, but remember to alter the email addresses.
```
To: yourmail@gmail.com 
From: yourmail@gmail.com 
Subject: Testmessage 
This is a test for sending
```
Run the command:

`ssmtp -v yourmail@gmail.com < test.txt`

Status messages should indicated that the mail was sent successfully. If there are no errors, you can then check out `yourmail@gmail.com` and make sure that email has been delivered successfully. But, if you do get errors, recheck your configuration settings in `/usr/local/etc/ssmtp/ssmtp.conf`. If you don't receive the email then check `/var/log/maillog`:

`cat /var/log/maillog`

Exit the jail `exit`.

## Configure the Reverse Proxy
If using Caddy, the code block might look something like:
```
blog.mydomain.com {
  encode gzip
  reverse_proxy http://192.168.1.4
}
```

## Set up WordPress
**IT'S ESSENTIAL THAT YOU SET UP WORDPRESS BEHIND A REVERSE PROXY BEFORE YOU PROCEED WITH THIS STEP. YOU WILL NOT BE ABLE TO RETROFIT WORDPRESS BEHIND A REVERSE PROXY LATER ON.**

You're now ready to do the famous five-minute WordPress installation. Do this by entering your WordPress site FQDN in a browser e.g. https://blog.mydomain.com

### Configure Redis
For WordPress to use Redis, install and activate the Redis Object Cache plugin. Using the plugin, `Enable Object Cache `.

### phpMyAdmin Considerations

You can log in to phpMyAdmin, with your database `wordpress` username and password, using the jail FQDN instead of the jail IP e.g. `https://blog.mydomain.com/phpmyadmin`. Follow the signposts to store phpMyAdmin configuration data in the `phpmyadmin` database.

**CAUTION**
>SECURITY NOTE: phpMyAdmin is an administrative tool that has had several remote vulnerabilities discovered in the past, some allowing remote attackers to execute arbitrary code with the web server's user credential. All known problems have been fixed, but the FreeBSD Security Team strongly advises that any instance be protected with an additional protection layer, e.g. a different access control mechanism implemented by the web server as shown in the example.  Do consider enabling phpMyAdmin only when it is in use.

One way to disable phpMyAdmin is to unlink it in the jail `rm /usr/local/www/wordpress/phpmyadmin`. This will disable access to phpMyAdmin via the well-known subdirectory path e.g. `https://blog.mydomain.com/phpmyadmin`. To reenable phpMyAdmin, link the subdirectory path again `ln -s /usr/local/www/phpMyAdmin /usr/local/www/wordpress/phpmyadmin`. Disable it again when finished. This approach isn't particularly convenient though.

If you're using a Caddy reverse proxy, it's straightforward to place phpMyAdmin behind an authorisation proxy. Refer to the blog post [Securing phpMyAdmin in a WordPress Jail](https://blog.udance.com.au/2020/09/29/securing-phpmyadmin-in-a-wordpress-jail/) for further details.

Refer to [Securing your phpMyAdmin installation](https://docs.phpmyadmin.net/en/latest/setup.html#securing) for other means of securing phpMyAdmin.

## References
1. [How to install WordPress](https://wordpress.org/support/article/how-to-install-wordpress/)
2. [Install WordPress with Nginx Reverse Proxy to Apache on Ubuntu 18.04 – Google Cloud](https://www.cloudbooklet.com/install-wordpress-with-nginx-reverse-proxy-to-apache-on-ubuntu-18-04-google-cloud/)
3. [SecureSSMTP](https://wiki.freebsd.org/SecureSSMTP)
4. [Using Gmail SMTP to send email in FreeBSD](http://easyos.net/articles/bsd/freebsd/using_gmail_smtp_to_send_email_in_freebsd)
5. [Requirements — phpMyAdmin 5.1.0-dev documentation](https://docs.phpmyadmin.net/en/latest/require.html)
6. [Mujahid Jaleel - My Life, My Blog](https://mujahidjaleel.blogspot.com/2018/10/how-to-setup-phpmyadmin-in-iocage-jail.html)
7. [Caching and Redis: Samuel Dowling - How to Install Nextcloud on FreeNAS in an iocage Jail with Hardened Security](https://www.samueldowling.com/2020/07/24/install-nextcloud-on-freenas-iocage-jail-with-hardened-security/)
8. [Redis Object Cache plugin for WordPress - Till Kruss](https://wordpress.org/plugins/redis-cache/)
9. [How to Improve Your Site Performance Using Redis Cache on WordPress](https://www.cloudways.com/blog/install-redis-cache-wordpress/)
10. [Some frequently asked questions about Predis](https://github.com/predis/predis/blob/main/FAQ.md)
11. [Administration Over SSL](https://wordpress.org/support/article/administration-over-ssl/)
12. [Editing wp-config.php](https://wordpress.org/support/article/editing-wp-config-php/)
