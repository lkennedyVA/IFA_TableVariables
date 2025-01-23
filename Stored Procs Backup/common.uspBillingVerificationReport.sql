USE [IFA]
GO

/****** Object:  StoredProcedure [common].[uspBillingVerificationReport]    Script Date: 1/22/2025 6:10:57 AM ******/
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
*****************************************************************************************/
ALTER PROCEDURE [common].[uspBillingVerificationReport]
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @iOrgId int 
		,@dt datetime = getdate();
    DECLARE @dtStartDate datetime2(7) = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 21:00:00.0000000')--end of month before last
        ,@dtEndDate datetime2(7) =  CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 20:59:59.9999999')--end of last month
		,@dtMonthStartDate date = DATEADD(MONTH,-1,@dt-(DATEPART(DAY,@dt)-1)) 
		,@iChannelDimensionId int = (SELECT DimensionId FROM [common].[Dimension] WHERE [Name] = N'Channel')
		,@iOrgDimensionId int = (SELECT DimensionId FROM [common].[Dimension] WHERE [Name] = N'Organization')
		,@iChannelOrgTypeId int = (SELECT OrgTypeId FROM [organization].[OrgType] WHERE [Name] = N'Channel')
		,@nvProfileName sysname = 'SSDB-PRDTRX01'
		,@nvFrom nvarchar(1000) = 'DBSupport@ValidAdvantage.com'
		,@nvHBody nvarchar(2000) = ''
		,@nvSubject nvarchar(1000) = 'BillingVerification';
		
	--PNC Billing
	SET @iOrgId = 100009;

	DROP TABLE IF EXISTS #tblOL;
	CREATE TABLE #tblOL (
		[LevelId] [nvarchar](25) NULL,
		[RelatedOrgId] [int] NULL,
		[OrgId] [int] NOT NULL PRIMARY KEY CLUSTERED,
		[OrgCode] [nvarchar](25) NULL,
		[OrgName] [nvarchar](50) NULL,
		[ExternalCode] [nvarchar](50) NULL,
		[OrgDescr] [nvarchar](255) NULL,
		[OrgTypeId] [int] NULL,
		[Type] [nvarchar](50) NULL,
		[ChannelId] [int] NULL,
		[ChannelName] [nvarchar](50) NULL,
		[StatusFlag] [int] NULL,
		[DateActivated] [datetime2](7) NULL,
		[UserName] [nvarchar](100) NULL
	);

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	--CLEAN OUT TABLE BEFORE USE
	DELETE FROM [dbo].[BillingVerification];

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'PNC Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] as p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
		AND i.ItemStatusID = 3
		AND i.Rulebreak = N'0'
		AND i.CheckAmount >= 25.00
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
		AND ca.code = N'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
		AND (p.OrgId = 100019
			OR
				(dol.LevelId = 5000
				AND p.OrgId <> 100019)
			OR
				(dol.LevelId = 6000
				AND p.OrgId <> 100019))
	GROUP BY dol.ChannelName;

	--MTB Billing
	SET @iOrgId = 100008

	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'M&T Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;

	--TD Billing
	SET @iOrgId = 100010

	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'TD Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
														AND i.Rulebreak = 0
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;

	--FTB Billing
	SET @iOrgId = 163769
	--2022-10-03 SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(10),(CONVERT(DATE,DATEADD(month,-1,getdate()-(datepart(day,getdate())))))) + ' 19:00:00.0000000') --end of month before last
	--2022-10-03 SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(10),(CONVERT(DATE,getdate()-(datepart(day,getdate())))))+' 18:59:59.9999999')	--end of last month
	SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 19:00:00.0000000')--end of month before last
    SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 18:59:59.9999999')--end of last month
	
	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'5/3 Bank',@dtMonthStartDate
		,CASE WHEN dol.ChannelName = 'Teller' AND pt.Code = 'Check' THEN 'Teller CC' ELSE  dol.ChannelName END  AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
													AND ca.code = 'Accepted'
	INNER JOIN [common].[ProcessType] pt WITH (READUNCOMMITTED) on p.ProcessTypeId = pt.ProcessTypeId
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
		AND ((p.OrgId = 164933
				AND pt.Code = 'IFA') 
																
				OR (p.OrgId <> 164933
					AND (pt.Code = 'IFA'
						OR pt.Code = 'Check')
					--AND i.Rulebreak = 0
				)
			)
	GROUP BY CASE WHEN dol.ChannelName = 'Teller' AND pt.Code = 'Check' THEN 'Teller CC' ELSE  dol.ChannelName END;

	--FNBPA
	SET @iOrgId = 172436
	--2022-10-03 SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(10),(CONVERT(DATE,DATEADD(month,-1,getdate()-(datepart(day,getdate())))))) + ' 17:00:00.0000000') --end of month before last
	--2022-10-03 SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(10),(CONVERT(DATE,getdate()-(datepart(day,getdate())))))+' 16:59:59.9999999')	--end of last month
	SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 17:00:00.0000000')--end of month before last
    SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 16:59:59.9999999')--end of last month

	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'FNBPA Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
														AND i.Rulebreak = 0
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;

	--KEY Billing
	SET @iOrgId = 179612
	--2022-10-03 SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(10),(CONVERT(DATE,DATEADD(month,-1,getdate()-(datepart(day,getdate())))))) + ' 19:00:00.0000000') --end of month before last
	--2022-10-03 SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(10),(CONVERT(DATE,getdate()-(datepart(day,getdate())))))+' 18:59:59.9999999')	--end of last month
	SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 22:00:00.0000000')--end of month before last
    SET @dtEndDate =  CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 21:59:59.9999999')--end of last month
	
	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'KEY Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
													AND i.Rulebreak = 0
													AND (i.ItemStatusID = 3 --2023-08-02
														OR i.ItemStatusID = 2 
															AND i.ClientAcceptedId = 1)														
														--AND i.ItemStatusID = 3 --2023-08-02													
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;

	--TFB Billing
	--2023-09-01
	SET @iOrgId = 179912;
	SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 20:00:00.0000000'); --end of month before last
    SET @dtEndDate =  CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 19:59:59.9999999'); --end of last month
	
	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'TFB Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
														AND i.Rulebreak = 0
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;

	--BMO Billing 
	--2024-05-01
	SET @iOrgId = 180467;
	SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 20:00:00.0000000'); --end of month before last
    SET @dtEndDate =  CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 19:59:59.9999999'); --end of last month
	
	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'BMO Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
														AND i.Rulebreak = 0
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;

	--CMB Billing 
	--2024-11-04
	SET @iOrgId = 181434;
	SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(DAY, -1, (DATEADD(MONTH, DATEDIFF(MONTH, 0, @dt)-1, 0))),121)+' 19:00:00.0000000'); --end of month before last
    SET @dtEndDate =  CONVERT(DATETIME2(7),CONVERT(nvarchar(10),DATEADD(MONTH, DATEDIFF(MONTH, -1, @dt)-1, -1),101)+' 18:59:59.9999999'); --end of last month

	--CLEAN OUT PRIOR ORG STRUCTURE
	DELETE FROM #tblOL;

	INSERT INTO #tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], ChannelId,ChannelName,StatusFlag)
	SELECT LevelId, ParentId, dol.OrgId, OrgCode, OrgName, dol.ExternalCode, OrgDescr, TypeId, [Type], TRY_CONVERT(INT,oc.Code),oc.[Name],dol.StatusFlag
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId) dol
	INNER JOIN [organization].[OrgXref] ox on dol.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimensionId
										AND ox.StatusFlag = 1
	INNER JOIN [organization].[Org] oc on ox.OrgParentId = oc.OrgId
	WHERE dol.TypeId <> @iChannelOrgTypeId
	ORDER BY dol.OrgId; 

	INSERT INTO [dbo].[BillingVerification]([ClientName], [MonthStartDate], [Channel], [IFAItemsAdopted], [IFAAmountAdopted], [DateCreated])
	SELECT N'CMB Bank',@dtMonthStartDate,dol.ChannelName AS 'Channel'
		,COUNT(p.processKey) AS 'IFAItemsAdopted'
		,SUM(i.CheckAmount) AS 'IFAAmountAdopted'
		,SYSDATETIME() AS 'DateCreated'
	FROM [ifa].[Process] p WITH (READUNCOMMITTED)
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) on p.ProcessId = i.ProcessId
														AND i.ItemStatusID = 3
														AND i.Rulebreak = 0
	INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) on p.CustomerId = cix.CustomerId
																		AND cix.IdTypeId = 25
	INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) on i.ClientAcceptedId = ca.ClientAcceptedId
																AND ca.code = 'Accepted'
	INNER JOIN #tblOL dol on p.OrgId = dol.OrgId
	WHERE p.DateActivated BETWEEN @dtStartDate AND @dtEndDate
	GROUP BY dol.ChannelName;
		
	--ADD ADDITIONAL CLIENTS HERE
	--set OrgId, Start and End dates, delete from #tblOL, load specific to OrgId
	--load [dbo].[BillingVerification] and it will be included in HTML below...
	--ADD ADDITIONAL CLIENTS HERE

	SET @nvHBody = '<html><table cellpadding="2" cellspacing="2" border="2"> '+'<tr><th>Prior Month</th></tr>' +
			'<table cellpadding="2" cellspacing="2" border="2"> <tr><th>ClientName</th><th>MonthStartDate</th><th>Channel</th><th>ItemsAdopted</th><th>AmountAdopted</th><th>DateCreated</th></tr>' + 
		replace(replace((SELECT td = bv.ClientName +'</td><td>' +
							CONVERT(NVARCHAR(10),bv.MonthStartDate) +'</td><td>'+
							bv.Channel +'</td><td>'+
							FORMAT(bv.IFAItemsAdopted, 'N', 'en-us') +'</td><td>'+ 
							FORMAT(bv.IFAAmountAdopted , 'N', 'en-us') +'</td><td>'+
							CONVERT(nvarchar(25),bv.DateCreated,121) 
						FROM [dbo].[BillingVerification] as  bv 
						ORDER BY bv.ClientName
						FOR XML PATH('tr')), '&lt;', '<'), '&gt;', '>') + '</table></table></html>' 

	SELECT @nvHBody as Body;
END
GO


