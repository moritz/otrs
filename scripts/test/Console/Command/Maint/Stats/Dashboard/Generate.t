# --
# Maint/Stats/Dashboard/Generate.t - command tests
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

## no critic (Modules::RequireExplicitPackage)
use strict;
use warnings;
use utf8;

use vars (qw($Self));

my $CommandObject = $Kernel::OM->Get('Kernel::System::Console::Command::Maint::Stats::Dashboard::Generate');

my $ExitCode = $CommandObject->Execute();

# just a very simple test to see if the script can be executed without errors
$Self->Is(
    $ExitCode,
    0,
    "Maint::Stats::Dashboard::Generate exit code",
);

1;
