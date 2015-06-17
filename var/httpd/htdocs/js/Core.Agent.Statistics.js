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
            var $Link = $(this);

            $('.BigButtons li a').removeClass('Active');
            $(this).addClass('Active');

            $('#GeneralSpecifications').fadeIn(function() {

                $('#GeneralSpecifications .Content').addClass('Center').html('<span class="AJAXLoader"></span>');
                $('#SaveWidget').hide();

                var URL = Core.Config.Get('Baselink'),
                Data = {
                    Action: 'AgentStatistics',
                    Subaction: 'GeneralSpecificationsWidgetAJAX',
                    StatisticPreselection: $Link.data('statistic-preselection')
                };
                Core.AJAX.FunctionCall(URL, Data, function(Response) {
                    $('#GeneralSpecifications .Content').removeClass('Center').html(Response);
                    $('#SaveWidget').show();
                }, 'html');
            });

            return false;
        });
    };

    function RebuildEditXAxisDialogAddSelection() {
        $('#EditXAxisDialogAddAttribute').empty();
        $.each($('#XAxisWidgetContainer .XAxisElement'), function() {
            var $XAxisElement = $(this),
                $Option = $($.parseHTML('<option></option>'));

            $Option.val($XAxisElement.data('element'))
                .text($XAxisElement.find('> label').text())
                .appendTo('#EditXAxisDialogAddAttribute');

        });
    }

    function RefreshEditXAxisDialogContent() {
        RebuildEditXAxisDialogAddSelection();
        if ($('#EditXAxisDialogField').children().length) {
            $('#EditXAxisDialogAdd').hide();
        }
        else {
            $('#EditXAxisDialogAdd').show();
        }
    }

    TargetNS.XAxisElementAdd = function(ElementName) {
        var $Element = $('#XAxisWidgetContainer #XAxisElement' + ElementName);
        $Element.appendTo($('#EditXAxisDialogField'));
        RefreshEditXAxisDialogContent();
    };

    TargetNS.XAxisElementDelete = function(ElementName) {
        var $Element = $('#EditXAxisDialogField #XAxisElement' + ElementName);
        $Element.appendTo($('#XAxisWidgetContainer'));
        RefreshEditXAxisDialogContent();
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
        $('button.EditXAxis').on('click', function() {
            function XAxisEditDialogClose() {
                $('#EditXAxisDialogTemplateContent').appendTo('#EditXAxisDialogTemplate');
                RefreshEditXAxisDialogContent();
                Core.UI.Dialog.CloseDialog($('.Dialog'));
            }
            RefreshEditXAxisDialogContent();
            Core.UI.Dialog.ShowContentDialog('<div id="XAxisEdit" style="max-height: 500px; overflow: auto;"></div>', '123', 100, 100, true, [{Label: "Apply", Type: 'Close', Function: XAxisEditDialogClose}], false);
            $('#EditXAxisDialogTemplateContent').appendTo('#XAxisEdit');

            return false;
        });

        $('#EditXAxisDialogAdd .AddButton').on('click', function(){
            TargetNS.XAxisElementAdd($('#EditXAxisDialogAddAttribute').val());
            return false;
        });

        $('#EditXAxisDialogField').on('click', '.DeleteButton', function(){
            TargetNS.XAxisElementDelete($(this).parents('.XAxisElement').data('element'));
            return false;
        });
    };


    return TargetNS;
}(Core.Agent.Statistics || {}));
