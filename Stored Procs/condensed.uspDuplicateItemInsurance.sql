USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [condensed].[uspDuplicateItemInsurance]
	Created By: Larry Dugger
	Descr:  This procedure picks up any missing items from yesterday
	Tables: [ifa].[Item]
		,[payer].[Payer]
	Functions: [ifa].[ufnDuplicateItemMac]
		,[ifa].[ufnDuplicateItemExists]

	History:
		2017-08-18 - LBD - Created
		2017-08-20 - LBD - Modified, added logging
		2017-08-26 - LBD - Adjusted the mis labeled log msg
		2017-12-15 - LBD - Modified, Close Gap Within Duplicate Processing  
			remove RuleBreak = 0
		2019-10-08 - LBD - Modified, added in consideration for HEB
		2020-12-10 - LBD - Making sure loggin is operating, remove HEB consideration
			,since it is no longer necessary (no trans being generated there)
		2023-12-12 - CBS - VALID-1479: For SmallWorld, only include ItemStatusId = 3 
			AND ClientAcceptedId = 1 to be added to the duplicate table
		2025-01-08 - LXK - Removed table variable
*****************************************************************************************/
ALTER PROCEDURE [condensed].[uspDuplicateItemInsurance]
	 @pbMonitor BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #DuplicateItemInsurance
	create table #DuplicateItemInsurance( 
		 ParentId int
		,OrgId int 
		,OrgName nvarchar(255)
		,ExternalCode nvarchar(50) 
	);
	DECLARE @iOrgClientId int --2023-12-12
		,@biRowCount bigint = 0
		,@dtBeginDay datetime2(7) = CONVERT(date, GETDATE()-1) --if you don't perform this way it will treat i.DateActivated as a 'date'
		,@dtEndDay datetime2(7) = CONVERT(date, GETDATE()); 

	--If we have to add another client, convert this section to a table valued function with a reference table including the Orgs
	SELECT @iOrgClientId = OrgId --2023-12-12
	FROM [organization].[Org] o
	INNER JOIN [organization].[OrgType] ot
		ON o.OrgTypeId = ot.OrgTypeId
	WHERE o.[Name] = 'SmallWorld Client'
		AND ot.[Name] = 'Client';

	INSERT INTO #DuplicateItemInsurance( --2023-12-12
		 ParentId 
		,OrgId  
		,OrgName 
		,ExternalCode 
	)
	SELECT ParentId
		,OrgId
		,OrgName
		,ExternalCode
	FROM [common].[ufnDownOrgListByOrgId](@iOrgClientId);

	IF @pbMonitor = 0
	BEGIN
		INSERT INTO [dbo].[DuplicateItemLog](Cnt, Msg, DateActivated)
		SELECT 0,'uspDuplicateItemInsurance Enter',SYSDATETIME();

		--Typical Duplicate Item Processing Except for the locations excluded in #DuplicateItemInsurance... Those will be handled seperately.
		INSERT INTO [stat].[NewDuplicateItem](IdMac,DateActivated)
		SELECT [ifa].[ufnDuplicateItemMac](py.RoutingNumber, py.AccountNumber, i.CheckNumber), i.DateActivated
		FROM [ifa].[Process] p WITH (READUNCOMMITTED)
		INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) 
			ON p.ProcessId = i.ProcessId
		INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) 
			ON i.PayerId = py.PayerId
		LEFT JOIN #DuplicateItemInsurance dol --2023-12-12
			ON p.OrgId = dol.OrgId
		WHERE dol.OrgId IS NULL --2023-12-12
			AND i.DateActivated BETWEEN @dtBeginDay AND @dtEndDay
			AND i.ItemStatusId = 3
			AND i.CheckNumber <> N'0'
			AND [ifa].[ufnDuplicateItemExists](RoutingNumber, AccountNumber, CheckNumber) = 0
			AND NOT EXISTS (SELECT 'X' 
							FROM [stat].[NewDuplicateItem] WITH (READUNCOMMITTED)
							WHERE IdMac = [ifa].[ufnDuplicateItemMac](py.RoutingNumber, py.AccountNumber, i.CheckNumber))
		ORDER BY i.DateActivated DESC;

		SET @biRowCount = @@ROWCOUNT;

		--Exception Duplicate Item Processing for the locations included in #DuplicateItemInsurance... 
		INSERT INTO [stat].[NewDuplicateItem](IdMac,DateActivated)
		SELECT [ifa].[ufnDuplicateItemMac](py.RoutingNumber, py.AccountNumber, i.CheckNumber), i.DateActivated
		FROM [ifa].[Process] p WITH (READUNCOMMITTED)
		INNER JOIN #DuplicateItemInsurance dol --2023-12-12 
			ON p.OrgId = dol.OrgId
		INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) 
			ON p.ProcessId = i.ProcessId
		INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) 
			ON i.PayerId = py.PayerId
		WHERE i.ItemStatusId = 3
			AND i.ClientAcceptedId = 1
			AND i.DateActivated BETWEEN @dtBeginDay AND @dtEndDay
			AND i.CheckNumber <> N'0'
			AND [ifa].[ufnDuplicateItemExists](RoutingNumber, AccountNumber, CheckNumber) = 0
			AND NOT EXISTS (SELECT 'X' 
							FROM [stat].[NewDuplicateItem] WITH (READUNCOMMITTED)
							WHERE IdMac = [ifa].[ufnDuplicateItemMac](py.RoutingNumber, py.AccountNumber, i.CheckNumber))
		ORDER BY i.DateActivated DESC;

		SET @biRowCount += @@ROWCOUNT;
			   		 	  	  	   			
		INSERT INTO [dbo].[DuplicateItemLog](Cnt, Msg, DateActivated)		
		SELECT @biRowCount,'uspDuplicateItemInsurance Loaded Recordset',SYSDATETIME(); --2017-08-26 LBD 

		INSERT INTO [dbo].[DuplicateItemLog](Cnt, Msg, DateActivated)
		SELECT 0,'uspDuplicateItemInsurance Exit',SYSDATETIME();
	END
	ELSE --We are monitoring
	BEGIN
		--Typical Duplicate Item Processing Except for the locations excluded in #DuplicateItemInsurance... Those will be handled seperately.
		SELECT dol.OrgName, p.OrgId, i.ItemId, i.DateActivated, py.RoutingNumber, py.AccountNumber, i.CheckNumber --2023-12-12 
			,i.ItemStatusId, i.ClientAcceptedId, i.RuleBreak
		FROM [ifa].[Process] p WITH (READUNCOMMITTED)
		INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) 
			ON p.ProcessId = i.ProcessId
		INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) 
			ON i.PayerId = py.PayerId
		LEFT JOIN #DuplicateItemInsurance dol 
			ON p.OrgId = dol.OrgId
		WHERE dol.OrgId IS NULL
			AND i.DateActivated BETWEEN @dtBeginDay AND @dtEndDay
			AND i.ItemStatusId = 3
			AND i.CheckNumber <> N'0'
			AND [ifa].[ufnDuplicateItemExists](RoutingNumber, AccountNumber, CheckNumber) = 0
			AND NOT EXISTS (SELECT 'X' 
							FROM [stat].[NewDuplicateItem] WITH (READUNCOMMITTED)
							WHERE IdMac = [ifa].[ufnDuplicateItemMac](py.RoutingNumber, py.AccountNumber, i.CheckNumber))
		UNION ALL
		--Exception Duplicate Item Processing for the locations included in #DuplicateItemInsurance... 
		SELECT dol.OrgName, p.OrgId, i.ItemId, i.DateActivated, py.RoutingNumber, py.AccountNumber, i.CheckNumber --2023-12-12 
			,i.ItemStatusId, i.ClientAcceptedId, i.RuleBreak
		FROM [ifa].[Process] p WITH (READUNCOMMITTED)
		INNER JOIN #DuplicateItemInsurance dol 
			ON p.OrgId = dol.OrgId
		INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) 
			ON p.ProcessId = i.ProcessId
		INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) 
			ON i.PayerId = py.PayerId
		WHERE i.DateActivated BETWEEN @dtBeginDay AND @dtEndDay
			AND i.ItemStatusId = 3
			AND i.ClientAcceptedId = 1
			AND i.CheckNumber <> N'0'
			AND [ifa].[ufnDuplicateItemExists](RoutingNumber, AccountNumber, CheckNumber) = 0
			AND NOT EXISTS (SELECT 'X' 
							FROM [stat].[NewDuplicateItem] WITH (READUNCOMMITTED)
							WHERE IdMac = [ifa].[ufnDuplicateItemMac](py.RoutingNumber, py.AccountNumber, i.CheckNumber))
		ORDER BY i.DateActivated DESC;

	END
END
