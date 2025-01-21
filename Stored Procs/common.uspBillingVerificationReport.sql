USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspBillingVerificationReport]
	Created By: Larry Dugger
	Description: This procedure summarizes billing activity for the prior month.
		It doesn't automatically include new clients. But it does return 
		[dbo].[BillingVerification] which we pipe using xml into an HTML string for email.

		EXECUTE [common].[uspBillingVerificationReport]

	Tables: [ifa].[Process] 
		,[ifa].[Item]
		,[customer].[CustomerIdXref]
		,[common].[ClientAccepted]

	History:
		2022-06-09 - LBD - Created
		2022-10-03 - LBD - Modified, adjusted the date ranges on FNBPA and FTB VALID-507
		2023-06-21 - LBD - Modified, adding KEY VALID-1081
		2023-08-02 - CBS - VALID-1161: We need to add another condition to pick up Items 
			with an ItemStatusId = 2 (processed) and ClientAcceptedId = 1 (Accepted). 
			We're missing items updated by the 'Import Key Exception' process
		2023-09-01 - CBS - VALID-1237: Added TFB. Currently coded for the last day of the 
			month two months ago at 20:00:00.0000000 through last day of prior month 
			at 19:59:59.9999999 Central time.
		2023-11-16 - CDB - VALID-1419: Updated FTB logic to remove RuleBreak = 0 condition.
		2024-05-01 - CBS - VALID-1817: Added BMO
		2024-10-29 - CBS - VALID-2177: Added CMB
		2025-01-21 - LXK - Re-wrote proc, it was taking 18 seconds to run, it had repeative code that I consolidated, now running in 5 seconds.
*****************************************************************************************/
ALTER PROCEDURE [common].[uspBillingVerificationReport]
AS
BEGIN
	SET NOCOUNT ON
DECLARE @dt datetime = getdate()
DECLARE 
        @dtMonthStartDate date = DATEADD(MONTH,-1,@dt-(DATEPART(DAY,@dt)-1)),
        @iChannelDimensionId int = (SELECT DimensionId FROM [common].[Dimension] WHERE [Name] = N'Channel'),
        @iOrgDimensionId int = (SELECT DimensionId FROM [common].[Dimension] WHERE [Name] = N'Organization'),
        @iChannelOrgTypeId int = (SELECT OrgTypeId FROM [organization].[OrgType] WHERE [Name] = N'Channel'),
		@nvProfileName sysname = 'SSDB-PRDTRX01',
		@nvFrom nvarchar(1000) = 'DBSupport@ValidAdvantage.com',
		@nvHBody nvarchar(2000) = '',
		@nvSubject nvarchar(1000) = 'BillingVerification';

-- Configuration table for bank-specific settings
DECLARE @BankConfig TABLE (
    BankName nvarchar(50),
    OrgId int,
    TimeOffsetSeconds int,
    StartDate datetime2(7),
    EndDate datetime2(7),
    CheckAmountFilter decimal(18,2),
    RulebreakFilter bit,
    ItemStatusFilter nvarchar(100),
    ProcessTypeFilter nvarchar(100),
    PRIMARY KEY (OrgId)
);

-- Insert bank configurations
INSERT INTO @BankConfig (BankName, OrgId, TimeOffsetSeconds, CheckAmountFilter, RulebreakFilter, ItemStatusFilter, ProcessTypeFilter)
SELECT BankName, OrgId, TimeOffsetSeconds, CheckAmountFilter, RulebreakFilter, ItemStatusFilter, ProcessTypeFilter
FROM (VALUES 
    ('PNC Bank',    100009, 75600, 25.00,  NULL,  '3',     NULL),
    ('M&T Bank',    100008, 75600, 0.00,   NULL,  '3',     NULL),
    ('TD Bank',     100010, 75600, 0.00,   0,     '3',     NULL),
    ('5/3 Bank',    163769, 68400, 0.00,   NULL,  '3',     'IFA,Check'),
    ('FNBPA Bank',  172436, 61200, 0.00,   0,     '3',     NULL),
    ('KEY Bank',    179612, 79200, 0.00,   0,     '2,3',   NULL),
    ('TFB Bank',    179912, 72000, 0.00,   0,     '3',     NULL),
    ('BMO Bank',    180467, 72000, 0.00,   0,     '3',     NULL),
    ('CMB Bank',    181434, 68400, 0.00,   0,     '3',     NULL)
) AS BankData(BankName, OrgId, TimeOffsetSeconds, CheckAmountFilter, RulebreakFilter, ItemStatusFilter, ProcessTypeFilter);

-- Calculate date ranges from table variable @BankConfig
UPDATE @BankConfig
SET StartDate = DATEADD(SECOND, TimeOffsetSeconds, CONVERT(DATETIME2(7), EOMONTH(DATEADD(MONTH, -2, @dt)))),
    EndDate = DATEADD(SECOND, TimeOffsetSeconds - 1, CONVERT(DATETIME2(7), EOMONTH(DATEADD(MONTH, -1, @dt))));

CREATE TABLE #OrgStructure (
    BankName nvarchar(50),
    OrgId int,
    LevelId nvarchar(25),
    ChannelName nvarchar(50),
    ProcessTypeFilter nvarchar(100),
    StartDate datetime2(7),
    EndDate datetime2(7),
    CheckAmountFilter decimal(18,2),
    RulebreakFilter bit,
    ItemStatusFilter nvarchar(100),
    PRIMARY KEY (BankName, OrgId)
);

INSERT INTO #OrgStructure
SELECT 
    bc.BankName,
    dol.OrgId,
    dol.LevelId,
    oc.Name AS ChannelName,
    bc.ProcessTypeFilter,
    bc.StartDate,
    bc.EndDate,
    bc.CheckAmountFilter,
    bc.RulebreakFilter,
    bc.ItemStatusFilter
FROM @BankConfig bc
CROSS APPLY [common].[ufnDownDimensionByOrgIdILTF](bc.OrgId, @iOrgDimensionId) dol
INNER JOIN [organization].[OrgXref] ox ON dol.OrgId = ox.OrgChildId AND ox.DimensionId = @iChannelDimensionId AND ox.StatusFlag = 1
INNER JOIN [organization].[Org] oc ON ox.OrgParentId = oc.OrgId
WHERE dol.TypeId <> @iChannelOrgTypeId;

CREATE TABLE #BillingVerification (
    Id int IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    ClientName nvarchar(50),
    MonthStartDate date,
    Channel nvarchar(50),
    IFAItemsAdopted int,
    IFAAmountAdopted money,
    DateCreated datetime2(7)
);

INSERT INTO #BillingVerification (ClientName, MonthStartDate, Channel, IFAItemsAdopted, IFAAmountAdopted, DateCreated)
SELECT 
    os.BankName,
    @dtMonthStartDate,
    CASE 
    WHEN os.BankName = '5/3 Bank' AND os.ChannelName = 'Teller' AND pt.Code = 'Check' THEN 'Teller CC' 
    ELSE os.ChannelName 
    END AS Channel,
    COUNT(p.processKey) AS IFAItemsAdopted,
    SUM(i.CheckAmount) AS IFAAmountAdopted,
    SYSDATETIME() AS DateCreated
FROM #OrgStructure os
INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) ON p.OrgId = os.OrgId AND p.DateActivated BETWEEN os.StartDate AND os.EndDate
INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId 
AND (os.CheckAmountFilter IS NULL 
OR i.CheckAmount >= os.CheckAmountFilter) 
AND (os.RulebreakFilter IS NULL OR i.Rulebreak = os.RulebreakFilter) 
AND i.ItemStatusID IN (
SELECT value FROM STRING_SPLIT(os.ItemStatusFilter, ','))
INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) ON p.CustomerId = cix.CustomerId AND cix.IdTypeId = 25
INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId AND ca.code = 'Accepted'
LEFT JOIN [common].[ProcessType] pt WITH (READUNCOMMITTED) ON p.ProcessTypeId = pt.ProcessTypeId
WHERE (os.ProcessTypeFilter IS NULL 
OR pt.Code IN (SELECT value FROM STRING_SPLIT(os.ProcessTypeFilter, ','))) AND (os.BankName != '5/3 Bank' 
OR (p.OrgId = 164933 AND pt.Code = 'IFA')
OR (p.OrgId != 164933 AND pt.Code IN ('IFA', 'Check')))
GROUP BY os.BankName,
CASE WHEN os.BankName = '5/3 Bank' AND os.ChannelName = 'Teller' AND pt.Code = 'Check' THEN 'Teller CC' 
ELSE os.ChannelName 
END;



--SELECT * 
--FROM #BillingVerification 
--ORDER BY ClientName;
--Select * from dbo.BillingVerification order by ClientName

SET @nvHBody = '<html><table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>Prior Month</th></tr>' +
'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>ClientName</th><th>MonthStartDate</th><th>Channel</th><th>ItemsAdopted</th><th>AmountAdopted</th><th>DateCreated</th></tr>' + 
replace(replace((SELECT td = bv.ClientName +'</td><td>' +
CONVERT(NVARCHAR(10),bv.MonthStartDate) +'</td><td>'+
bv.Channel +'</td><td>'+
FORMAT(bv.IFAItemsAdopted, 'N', 'en-us') +'</td><td>'+ 
FORMAT(bv.IFAAmountAdopted , 'N', 'en-us') +'</td><td>'+
CONVERT(nvarchar(25),bv.DateCreated,121) 
FROM #BillingVerification as  bv 
ORDER BY bv.ClientName
FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table></html>' 

SELECT @nvHBody as Body;

DROP TABLE #OrgStructure;
DROP TABLE #BillingVerification;

END