# apt-packageserver

When I was looking for an easy way to set up a repository, I couldn't find one and was flooded with different options and confusing/contradicting information. None of the guides seemed to be suitable for my situation, so I compiled the information and started creating a script to offload all the setup and manual labour involved.

Shell script to easily create and maintain a signed repository. Currently only tested on Ubuntu 12.04/precise.

It helps with the following:
- Generating GPG keys
- Signing .deb files with the correct GPG key
- Managing multiple distributions
- Auto cleanup/checking of the repository
- Process incoming directories
- Add packages manually

## Getting started for the impatient

```
$ ./packageserver.sh -s > ~/.packageserver
$ vim ~/.packageserver
>>>> Edit the config file with your favorite editor
$ sudo apt-get install dpkg-sig reprepro gnupg
$ ./packageserver.sh --generategpg
$ 
```
Now make sure your `TARGETDIR` is served by a webserver.

To add packages, put them in your incoming directory, and run the `packageserver.sh` script again without any packages. They should be added automatically.

If you manually want to specify the files on the commandline, you can do this with the following command:
```
$ ./packageserver.sh precise /path/to/mypackage-1.0.deb
```
Where `precise` is the distribution, or if you want to add to all distributions configured, specify `all`. This should sign the package and import it in your repository.

## Getting started

### Initial config file

If you run the `packageserver.sh` script for the first time, without any paramters, it will tell you some pointers where to start. To run correctly, you need a config-file somewhere. This config file can be generated with the `-s` or `--sampleconfig` parameter, which spams a basic config-file skeleton to stdout.

Config files can be specified while running with the `-c` or `--config` parameter. Config files are loaded in the following order (if they exist):

1. `/etc/default/packageserver` - global configuration file
2. `$HOME/.packageserver` - local configuration file of the user running the script
3. any file specified with the `-c` or `--config` parameter.

Note that *all* configuration files are loaded. Even if you specify one on the commandline, the first 2 will be loaded first, but all settings there will be overwritten by any config file loaded at a later stage.

To get started, run the following command:
```
./packageserver.sh -s > ~/.packageserver
```

Then use your favorite editor to fill in the blanks in the `~/.packageserver` configuration file.

### Installing dependencies

When your configuration is correct, and you try to run the `packageserver.sh` script, it's very likely that it will provide you with the following error:

```
$ ./packageserver.sh
INFO  [2013-04-11 12:15:25] Loaded custom configuration for Your organisation name.
ERROR [2013-04-11 12:15:25] The following required packages don't seem to be installed:  dpkg-sig reprepro
ERROR [2013-04-11 12:15:25] Aborting...
$
```

Install the packages listed there (`dpkg-sig` and `reprepro` in this example) with `sudo apt-get install`

### Generating the GPG key

Next time you run the `packageserver.sh` you'll probably don't have a gpg key, and you will be presented with the following error:

```
$ ./packageserver.sh
INFO  [2013-04-11 12:21:02] Loaded custom configuration for Your organisation name.
ERROR [2013-04-11 12:21:02] Signing key not available -- package signing disabled, use -g to generate GPG key
ERROR [2013-04-11 12:21:02] Aborting...
$
```

If you want a very basic setup and don't really care about the GPG key, you can run the following command to generate the key:
```
$ ./packageserver.sh --generategpg
INFO  [2013-04-11 12:25:32] Loaded custom configuration for Your organisation name.
gpg: skipping control `%no-ask-passphrase' ()
+++++
.........+++++
..+++++
..+++++
gpg: key CE85C03C marked as ultimately trusted
Key generation finished.
$ 
```

#### Using your own key

If you already have a key, you can import it in the keyring of the user running the command and make sure the `DEB_KEYNAME` in your config file is set to the name of the key.

Note that this requires a "sub" key to be present. You can check this by importing the key and running:

```
$ gpg --list-keys packages.yourorganisation
pub   2048R/CE85C03C 2013-04-11
uid                  packages.yourorganisation (yourorganisation package server) <packages@yourorganisation.com>
sub   2048R/7AF464DB 2013-04-11
$
```

Where `packages.yourorganisation` is the name of your key. It should have a simular output, most notably, the line starting with `sub`. If this works, just set the `DEB_KEYNAME` setting in your config file to your keyname.

### First run

Let's try one more time. This time, you should get output like this:

```
$ ./packageserver.sh
INFO  [2013-04-11 12:32:14] Loaded custom configuration for Your organisation name.
Exporting key...
INFO  [2013-04-11 12:32:14] ## Processing distribution precise
INFO  [2013-04-11 12:32:14] Checking distribution repository...
INFO  [2013-04-11 12:32:14] Processing incoming directories
INFO  [2013-04-11 12:32:14] Cleaning up repository...
INFO  [2013-04-11 12:32:14] Finished.
$
```

This means everything went fine! The directories were created, the distribution configuration was updated, and your "incoming" directory was processed (which should not contain any files yet).

## Importing packages


### Incoming directories

When running with no distribution or files specified, all `.deb` files in your in incoming directory are processed and added to *all* distributions specified. Files in the `all` subdirectory will also be added to all distributions.

If you want a .deb file only to be available for one distribution, make a subdirectory in your incoming directory with the name of the distribution, and put it there.

**IMPORTANT NOTE**: If the `ARCHDIR` setting is not empty, your (unsigned) `.deb` files are moved to this directory. If the `ARCHDIR` is empty, the files are **REMOVED**.


### Importing packages on commandline

You can also choose to import packages on the commandline. You can specify multiple packages at once, but you are limited to one distribution, unless you choose the `all` distribution which will import the packages into the repository of all configured distributions.

You do this like this:

```
$ ./packageserver.sh precise /path/to/package-1.0.deb /path/to/anotherpackage-1.0.deb
...
$
```

In this command `precise` is the distribution, followed by multiple `.deb` files.

Files processed this way are left untouched and **not** archived or removed.


## Pitfalls/known issues

1. Distributions cannot be removed from the repository
2. GPG keys cannot have a passphrase at the moment. This is "unsecure".

## Configuring the web-server

Next up is your webserver configuration. This is something the script does not provide (yet?). Just configure Apache or your webserver of choice to serve the `TARGETDIR` directory.

## Using your repository on a client

The public key will automatically be exported and be available on the `http://<your.package.server/url>/conf/<DEB_KEYNAME>.gpg.key` url if you configured your webserver correctly.

You can then import this key on the client by running this (replace url and DEB_KEYNAME according to your settins):
```wget -q -O - http://<your.package.server/url>/conf/<DEB_KEYNAME>.gpg.key | sudo apt-key add -```

Then you add the apt-source by running something like this:
```sudo echo "deb http://<your.package.server/url> <distributionname> main" > /etc/apt/sources.list.d/00-myorganisation.list```

Then run a `sudo apt-get update`, and your repository should be available to your client!


