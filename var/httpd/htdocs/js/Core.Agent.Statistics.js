// --
// Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.Statistics
 * @memberof Core.Agent
 * @author OTRS AG
 * @description
 *      This namespace contains the special module functions for the Statistics module.
 */
Core.Agent.Statistics = (function (TargetNS) {

    /**
     * @name InitAddScreen
     * @memberof Core.Agent.Statistics
     * @function
     * @description
     *      Initialize the add screen. Contains basically some logic to react on which
     *      of the big select buttons the agent uses. Afterwards, the specification widget
     *      is being loaded according to the clicked button.
     */
    TargetNS.InitAddScreen = function () {

        $('.BigButtons li a').bind('click', function () {

            $('.BigButtons li a').removeClass('Active');
            $(this).addClass('Active');

            $('#GeneralSpecifications').fadeIn(function() {

                $('#GeneralSpecifications .Content').addClass('Center').html('<span class="AJAXLoader"></span>');

                var URL = Core.Config.Get('Baselink'),
                Data = {
                    Action: 'AgentStatistics',
                    Subaction: 'GeneralSpecificationsWidgetAJAX'
                };

                Core.AJAX.FunctionCall(URL, Data, function(Response) {
                    $('#GeneralSpecifications .Content').removeClass('Center').html(Response);
                }, 'html');
            });

            return false;
        });
    };

    /**
     * @name InitEditScreen
     * @memberof Core.Agent.Statistics
     * @function
     * @description
     *      Initialize the add screen. Contains basically some logic to react on which
     *      of the big select buttons the agent uses. Afterwards, the specification widget
     *      is being loaded according to the clicked button.
     */
    TargetNS.InitEditScreen = function () {

        $('.SwitchView .fa').on('click', function() {
            if ($(this).hasClass('SwitchViewTable')) {
                $('.PreviewCanvas').fadeOut();
                $('.PreviewTable').fadeIn();
                $(this).fadeOut();
                $(this).parent().find('.SwitchViewGraph').fadeIn();
            }
            else {
                $('.PreviewTable').fadeOut();
                $('.PreviewCanvas').fadeIn();
                $(this).fadeOut();
                $(this).parent().find('.SwitchViewTable').fadeIn();
            }
        });
    };


    return TargetNS;
}(Core.Agent.Statistics || {}));
