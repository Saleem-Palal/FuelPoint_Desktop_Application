FuelPoint Station OS
Client installation instructions
Publisher: RetroSoft


DOUBLE-CLICK THIS FILE
----------------------
  Install.cmd

That is the full installer. Keep these files in the SAME folder:

  Install.cmd                    Double-click this
  install_fuelpoint_bundle.ps1   Used by Install.cmd (do not run this yourself)
  FuelPoint Station OS.msix      The application
  FuelPointDevCert.cer           The RetroSoft certificate
  DISTRIBUTION_README.txt        This file


WHAT HAPPENS
------------
  1. Double-click Install.cmd.
  2. Windows asks for Administrator permission. Click Yes.
  3. A black setup window installs the certificate, then the application.
  4. When you see "Setup complete", FuelPoint Station OS is installed.
     It may open by itself. You can also find it on the Start menu.

You do not need to open PowerShell, and you do not need to double-click
the .msix yourself.


UPDATES
-------
Copy the new files into the same folder (replace the old .msix) and
double-click Install.cmd again. You usually do not need a new certificate.


IF DOUBLE-CLICK DOES NOTHING, OR WINDOWS BLOCKS THE SCRIPT
----------------------------------------------------------
Right-click Install.cmd and choose "Run as administrator".

If Windows still says the publisher is not verified, turn on sideloading:

  Windows 10:  Settings > Update & Security > For developers > Sideload apps
  Windows 11:  Settings > Privacy & security > For developers > Developer Mode
               or Settings > Apps > Advanced app settings
               > Choose where to get apps > Anywhere


MANUAL INSTALL (only if Install.cmd cannot be used)
---------------------------------------------------
  1. Right-click Start > Windows Terminal (Admin) or Windows PowerShell (Admin).
  2. Go to this folder, then run:

       powershell -ExecutionPolicy Bypass -File .\install_client_cert.ps1 -IncludeRoot

  3. Double-click "FuelPoint Station OS.msix" and click Install or Update.


SUPPORT
-------
Do not install FuelPointDevCert.pfx on client PCs. That file is the private
signing key and stays on the RetroSoft build machine only.

Questions: contact RetroSoft with the station name and Windows version.
