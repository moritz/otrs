# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Dashboard::Stats;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use Kernel::System::Stats;
use Kernel::Output::HTML::Statistics::View;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    # Settings
    $Self->{PrefKeyStatsConfiguration} = 'UserDashboardStatsStatsConfiguration' . $Self->{Name};

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    # get StatID
    my $StatID = $Self->{Config}->{StatID};

    # get stats object
    my $StatsObject = Kernel::System::Stats->new(
        UserID => $Self->{UserID},
    );

    my $StatsViewObject = Kernel::Output::HTML::Statistics::View->new(
        StatsObject => $StatsObject,
    );

    my $Stat = $StatsObject->StatsGet( StatID => $StatID );

    # get the object name
    if ( $Stat->{StatType} eq 'static' ) {
        $Stat->{ObjectName} = $Stat->{File};
    }

    # if no object name is defined use an empty string
    $Stat->{ObjectName} ||= '';

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');

    # check if the user has preferences for this widget
    my %Preferences = $UserObject->GetPreferences(
        UserID => $Self->{UserID},
    );
    my $StatsSettings;
    if ( $Preferences{ $Self->{PrefKeyStatsConfiguration} } ) {
        $StatsSettings = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
            Data => $Preferences{ $Self->{PrefKeyStatsConfiguration} },
        );
    }

    my %Format = %{ $Kernel::OM->Get('Kernel::Config')->Get('Stats::Format') || {}};

    my %FilteredFormats;
    for my $Key (sort keys %Format) {
        $FilteredFormats{$Key} = $Format{$Key} if $Key =~ m{^D3}smx;
    }

    my $StatsViewParameterWidget = $StatsViewObject->StatsViewParameterWidget(
        Stat         => $Stat,
        UserGetParam => $StatsSettings,
        IsCacheable  => 1,
        Formats      => \%FilteredFormats,
    );

    my $SettingsHTML = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardStatsSettings',
        Data         => {
            %{$Stat},
            JSONFieldName            => $Self->{PrefKeyStatsConfiguration},
            NamePref                 => $Self->{Name},
            StatsViewParameterWidget => $StatsViewParameterWidget,
        },
    );

    my @Params = (
        {
            Desc  => 'Stats Configuration',
            Name  => $Self->{PrefKeyStatsConfiguration},
            Block => 'RawHTML',
            HTML  => $SettingsHTML,
        },
    );

    return @Params;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} }
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $StatID = $Self->{Config}->{StatID};

    my %Preferences = $Kernel::OM->Get('Kernel::System::User')->GetPreferences(
        UserID => $Self->{UserID},
    );
    my $StatsSettings = {};

    # get JSON object
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    if ( $Preferences{ $Self->{PrefKeyStatsConfiguration} } ) {
        $StatsSettings = $JSONObject->Decode(
            Data => $Preferences{ $Self->{PrefKeyStatsConfiguration} },
        );
    }

    # get stats object
    my $StatsObject = Kernel::System::Stats->new(
        UserID => $Self->{UserID},
    );

    my $CachedData = $StatsObject->StatsResultCacheGet(
        StatID       => $StatID,
        UserGetParam => $StatsSettings,
    );

    my $Format = $StatsSettings->{Format};
    if (!$Format) {
        my $Stat = $StatsObject->StatsGet( StatID => $StatID );
        STATFORMAT:
        for my $StatFormat (@{$Stat->{Format} || []}) {
            if ($StatFormat =~ m{^D3}smx) {
                $Format = $StatFormat;
                last STATFORMAT;
            }
        }
    }

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( defined $CachedData ) {
        my $JSON = $JSONObject->Encode(
            Data => $CachedData,
        );

        $LayoutObject->Block(
            Name => 'StatsData',
            Data => {
                Name      => $Self->{Name},
                StatsData => $JSON,
                Format    => $Format,
                ChartType => $StatsSettings->{ChartType} // 'Bar',
                Preferences => $Preferences{ 'GraphWidget' . $Self->{Name} } || '{}',
            },
        );

        my $Stat = $StatsObject->StatsGet( StatID => $StatID );

        # check permission for AgentStats
        my $StatsReg = $Kernel::OM->Get('Kernel::Config')->Get('Frontend::Module')->{'AgentStats'};
        my $StatsPermission;
        if ( !$StatsReg->{GroupRo} && !$StatsReg->{Group} ) {
            $StatsPermission = 1;
        }
        else {
            TYPE:
            for my $Type (qw(GroupRo Group)) {
                my $StatsGroups = ref $StatsReg->{$Type} eq 'ARRAY' ? $StatsReg->{$Type} : [ $StatsReg->{$Type} ];
                GROUP:
                for my $StatsGroup ( @{$StatsGroups} ) {
                    next GROUP if !$StatsGroup;
                    next GROUP if !$LayoutObject->{"UserIsGroupRo[$StatsGroup]"};
                    next GROUP if $LayoutObject->{"UserIsGroupRo[$StatsGroup]"} ne 'Yes';
                    $StatsPermission = 1;
                    last TYPE;
                }
            }
        }

        # add download buttons if agent has permission for AgentStats
        my $StatFormat = $Stat->{Format};
        if (
            $StatsPermission
            && IsArrayRefWithData($StatFormat)
            && grep { $_ eq 'Print' || $_ eq 'CSV' || $_ eq 'Excel' } @{$StatFormat}
            )
        {
            $LayoutObject->Block(
                Name => 'StatsDataLink',
                Data => {
                    Name => $Self->{Name},
                },
            );
            if ( grep { $_ eq 'CSV' } @{$StatFormat} ) {
                $LayoutObject->Block(
                    Name => 'StatsDataLinkCSV',
                    Data => {
                        Name   => $Self->{Name},
                        StatID => $StatID,
                    },
                );
            }
            if ( grep { $_ eq 'Excel' } @{$StatFormat} ) {
                $LayoutObject->Block(
                    Name => 'StatsDataLinkExcel',
                    Data => {
                        Name   => $Self->{Name},
                        StatID => $StatID,
                    },
                );
            }
            if ( grep { $_ eq 'Print' } @{$StatFormat} ) {
                $LayoutObject->Block(
                    Name => 'StatsDataLinkPDF',
                    Data => {
                        Name   => $Self->{Name},
                        StatID => $StatID,
                    },
                );
            }
        }
    }
    else {
        $LayoutObject->Block(
            Name => 'NoData',
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardStats',
        Data         => {
            Name => $Self->{Name},
        },
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
}

1;
