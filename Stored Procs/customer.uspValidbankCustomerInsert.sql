USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [customer].[uspValidbankCustomerInsert]
	CreatedBy: Chris Sharp 
	Description: This procedure insert Validbank Customers into IFA for the given time frame.
		We truncate [dbo].[Customer] and [dbo].[CustomerIdXref] at the start of the proc and
		load it with any Customers created in Validbank between the lower and upper bound datetime2s.
		We only migrate "Active" DL ProfileIdXref records (IdTypeId = 2)  

		** This procedure needs to be executed after step 5 of the 'Daily Validbank' job,
			'5	Clean ProfileIdXref records associated with invalid profiles, duplicates'

	Params:	@pdtLowerBoundDate DATETIME2(7)	
			Full: '2014-01-01 00:00:00.0000000'
			Differential: CONVERT(datetime2(7),CONVERT(DATE,GETDATE()-1))
		,@pdtUpperBoundDate DATETIME2(7)		
			Full: CONVERT(datetime2(7),CONVERT(DATETIME,DATEADD(HOUR,-1,GETDATE())))
			Differential: CONVERT(datetime2(7),CONVERT(DATE,GETDATE()))
		,@piPageSize INT 
			Full: 10000
			Differential: 1000

	Tables: [dbo].[Customer]
		,[dbo].[CustomerIdXref]
		,[customer].[Customer]
		,[customer].[CustomerIdXref]
		,[Validbank].[multipleidtype].[ProfileIdXref]
		,[Validbank].[dbo].[EN_CUST_PROFILE] 

	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2023-11-30 - CBS - VALID-1434: Created
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspValidbankCustomerInsert](
	 @pdtLowerBoundDate DATETIME2(7) = NULL
	,@pdtUpperBoundDate DATETIME2(7) = NULL
	,@piPageSize INT = 1000							
)
AS 
BEGIN
	SET NOCOUNT ON;

	DECLARE @dtLowerBoundDate datetime2(7) = ISNULL(@pdtLowerBoundDate,CONVERT(datetime2(7),CONVERT(DATE,GETDATE()-1)))
		,@dtUpperBoundDate datetime2(7) = ISNULL(@pdtUpperBoundDate,CONVERT(datetime2(7),CONVERT(DATE,GETDATE())))
		,@iPageSize int = @piPageSize
		,@iPageSeq int = 0 
		,@iMaxPageSeq int = -1 
		,@nvUserName nvarchar(100) = 'Validbank Migration'
		,@iErrorDetailId int = 0
		,@sSchemaName sysname = 'customer';

	--The Profile cleanup job doesn't occur until just after midnight...  We're going to be missing profiles since the DateActivated gets updated
	SET @dtUpperBoundDate = CONVERT(datetime2(7), DATEADD(MINUTE, 20, @dtUpperBoundDate)); 

	--Truncate them before proceeding with the insert
	TRUNCATE TABLE [dbo].[Customer];
	TRUNCATE TABLE [dbo].[CustomerIdXref];

	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY;
	INSERT INTO [dbo].[CustomerIdXref](
	     PageSeq 
		,CustomerId
		,IdTypeId
		,IdStateId
	    ,IdDecrypted
		,IdEncrypted
		,IdMac
		,Last4
		,OrgId
	    ,IdMac64
		,IdStateAbbr
		,StatusFlag
		,DateActivated
		,UserName
	)
	SELECT CONVERT(INT,CEILING((ROW_NUMBER() OVER (ORDER BY pix.ProfileID)) / @iPageSize)) AS PageSeq 
		,pix.ProfileID AS CustomerId
		,pix.IdTypeId
		,0 AS IdStateId
		,UPPER(RTRIM(LTRIM(CONVERT(nvarchar(50),DECRYPTBYKEY(pix.IdEncrypted))))) AS IdDecrypted
		,pix.IdEncrypted
		,pix.IdMac AS IdMac
		,pix.Last4 AS Last4
		,0 AS OrgId
		,NULL AS IdMac64
		,NULL AS IdStateAbbr
		,1 AS StatusFlag
		,SYSDATETIME() AS DateActivated
		,@nvUserName AS UserName
	FROM [Validbank].[multipleidtype].[ProfileIdXref] pix
	WHERE pix.DateActivated BETWEEN @dtLowerBoundDate AND @dtUpperBoundDate
		AND pix.IdTypeID = 2
		AND pix.StatusId = 1 --Only active profiles
		AND NOT EXISTS (SELECT 'X' 
						FROM [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED)
						WHERE pix.IdMac = cix.IdMac 
							AND pix.IdTypeID = cix.IdTypeId)
	ORDER BY pix.ProfileID ASC;
	CLOSE SYMMETRIC KEY VALIDSYMKEY; 

	--We have the list of Profiles that need to be created, but we need to remove any duplicates profiles on IdMac and IdTypeId
	--The goal is to leave the most recent ProfileID and the rest.  For this, we need to look outside of our time frame
	--ensure we account for all activity
	WITH cte_DedupeIdMac(RowId,ProfileId,IdTypeId,IdMac)
	AS (
		SELECT TOP (100) PERCENT ROW_NUMBER() OVER (PARTITION BY pix.IdMac, pix.IdTypeId ORDER BY pix.IdMac ASC, pix.IdTypeId ASC, pix.ProfileID DESC) AS RowId
			,pix.ProfileID 
			,pix.IdTypeId
			,pix.IdMac 
		FROM [dbo].[CustomerIdXref] cix0
		INNER JOIN [Validbank].[multipleidtype].[ProfileIdXref] pix
			ON cix0.IdMac = pix.IdMac
				AND cix0.IdTypeId = pix.IdTypeID
				AND cix0.CustomerId = pix.ProfileId 
		WHERE pix.IdTypeID = 2
		ORDER BY pix.IdMac ASC, pix.IdTypeId ASC, pix.ProfileID DESC 
		)
	--Testing... ProfileId 4748614 and IdMac 0x011124A62383D21B12F6C5384FA53A87582B6DC1 should remain. ProfileId 3127432 should be removed
	DELETE cix0
	FROM cte_DedupeIdMac cte
	INNER JOIN [dbo].[CustomerIdXref] cix0
		ON cte.ProfileId = cix0.CustomerId
	WHERE cte.RowId <> 1;

	--Add the StateAbbr from the Customer record to dbo.CustomerIdXref so we can establish the IdMac64
	UPDATE cix0
	SET cix0.IdStateAbbr = UPPER(RTRIM(LTRIM(ecp.PROFILE_STATE_ABV))) 
	FROM [dbo].[CustomerIdXref] cix0
	INNER JOIN [ValidBank].[dbo].[EN_CUST_PROFILE] ecp
		ON cix0.CustomerId = ecp.PROFILE_ID
	WHERE ISNULL(UPPER(RTRIM(LTRIM(ecp.PROFILE_STATE_ABV))), '') <> '';
		
	--Update the IdStateId based on the Customers address State
	UPDATE cix0
	SET cix0.IdStateId = ISNULL(s.StateId, 0)
	FROM [dbo].[CustomerIdXref] cix0
	LEFT JOIN [common].[State] s
		ON cix0.IdStateAbbr = s.Code;

	--Removing the entries without a IdStateId... 41,738
	DELETE cix0
	FROM [dbo].[CustomerIdXref] cix0
	WHERE cix0.IdStateId = 0;

	--Establish the IdMac64
	UPDATE cix0
	SET cix0.IdMac64 = [ifa].[ufnIdMac64](cix0.IdTypeId, cix0.OrgId, cix0.IdStateId, cix0.IdDecrypted)
	FROM [dbo].[CustomerIdXref] cix0;
	
	--Delete any records in [dbo].[CustomerIdXref] that exist in [customer].[Customer] with an matching IdTypeId and IdMac64 in [customer].[CustomerIdXref]. We don't want to create duplicates
	DELETE cix0
	FROM [dbo].[CustomerIdXref] cix0
	INNER JOIN [customer].[Customer] c WITH (READUNCOMMITTED)
		ON cix0.CustomerId = c.CustomerId
	WHERE EXISTS (SELECT 'X'
				FROM [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED)
				WHERE cix0.IdTypeId = cix.IdTypeId
					AND cix0.IdMac64 = cix.IdMac64);

	--Remove any duplicates profiles on IdMac64 and IdTypeId. The goal is to leave the most recent ProfileID
	WITH cte_DedupeIdMac(RowId,ProfileId,IdTypeId,IdMac64)
	AS (
		SELECT TOP (100) PERCENT ROW_NUMBER() OVER (PARTITION BY IdMac64, IdTypeId ORDER BY IdMac64 ASC, IdTypeId ASC, CustomerId DESC) AS RowId
			,CustomerId 
			,IdTypeId
			,IdMac64 
		FROM [dbo].[CustomerIdXref] 
		ORDER BY IdMac64 ASC, IdTypeId ASC, CustomerId DESC 
		)
	--Testing... ProfileId 6446862 and IdMac64 0x50843C0063C04DB10E6DC15AAEF2EF9388421F4C5A760AD8A3F1E54C4C3760686B13AD3B9907848048270A91A392396A331569AA57686E547B91EFC059090C35 should remain. ProfileId 4042867 should be removed
	DELETE cix0
	FROM cte_DedupeIdMac cte
	INNER JOIN [dbo].[CustomerIdXref] cix0
		ON cte.ProfileId = cix0.CustomerId
	WHERE cte.RowId <> 1;
	
	INSERT INTO [dbo].[Customer](
		 PageSeq 
		,CustomerId
		,OrgId
		,FirstName
		,LastName
		,DateOfBirth
		,WorkPhone
		,CellPhone
		,Email
		,DateEnrolled
		,StatusFlag
		,DateActivated
		,UserName
	)
	SELECT CONVERT(INT,CEILING((ROW_NUMBER() OVER (ORDER BY p.Profile_ID)) / @piPageSize)) AS PageSeq 
		,PROFILE_ID 
		,180705 AS OrgId --Brookshire Brothers
		,UPPER(RTRIM(LTRIM(SUBSTRING(PROFILE_FIRSTNAME,1,50)))) AS FirstName
		,UPPER(RTRIM(LTRIM(SUBSTRING(PROFILE_LASTNAME,1,50)))) AS LastName
		,DateOfBirth = CASE WHEN ISDATE(SUBSTRING(PROFILE_DOB,1,2)+'/'+SUBSTRING(PROFILE_DOB,3,2)+'/'+SUBSTRING(PROFILE_DOB,5,4)) = 1
							THEN CONVERT(DATE,SUBSTRING(PROFILE_DOB,1,2)+'/'+SUBSTRING(PROFILE_DOB,3,2)+'/'+SUBSTRING(PROFILE_DOB,5,4)) 
							ELSE NULL 
						END
		,WorkPhone = CASE WHEN PROFILE_PHONE1 = '' 
						THEN NULL 
						ELSE SUBSTRING(PROFILE_PHONE1,1,10) 
					END
		,CellPhone = CASE WHEN PROFILE_CELL = '' 
						THEN NULL 
						ELSE SUBSTRING(PROFILE_CELL,1,10) 
					END
		,SUBSTRING(PROFILE_EMAIL,1,100) AS Email
		,PROFILE_ENROLL_DATE AS DateEnrolled
		,1 AS StatusFlag
		,SYSDATETIME() AS DateActivated
		,@nvUserName AS UserName
	FROM [dbo].[CustomerIdXref] cix0
	INNER JOIN [Validbank].[dbo].[EN_CUST_PROFILE] p 
		ON cix0.CustomerId = p.PROFILE_ID
	WHERE NOT EXISTS (SELECT 'X' 
					FROM [customer].[Customer] c WITH (READUNCOMMITTED)
					WHERE p.PROFILE_ID = c.CustomerId)
	ORDER BY p.Profile_ID ASC;
		
	BEGIN TRY

		--As noted above, we NEED TO KEEP THE NUMBER OF RECORDS SMALL to prevent contention
		SELECT @iPageSeq = MIN(PageSeq)
			,@iMaxPageSeq = MAX(PageSeq)
		FROM [dbo].[Customer];

		WHILE @iPageSeq <= @iMaxPageSeq 
		BEGIN
			SET IDENTITY_INSERT [customer].[Customer] ON;

			INSERT INTO [customer].[Customer](
				 CustomerId
				,OrgId
				,FirstName
				,LastName
				,DateOfBirth
				,WorkPhone
				,CellPhone
				,Email
				,DateEnrolled
				,StatusFlag
				,DateActivated
				,UserName
			)
			SELECT CustomerId
				,OrgId
				,FirstName
				,LastName
				,DateOfBirth
				,WorkPhone
				,CellPhone
				,Email
				,DateEnrolled
				,StatusFlag
				,DateActivated
				,UserName
			FROM [dbo].[Customer] 
			WHERE PageSeq = @iPageSeq 
			ORDER BY CustomerId ASC;

			SET IDENTITY_INSERT [customer].[Customer] OFF;
		
			SET @iPageSeq += 1; 
			
			WAITFOR DELAY '00:00:02' 
		END

		SET @iPageSeq = 0; 
		SET @iMaxPageSeq = -1;
	
		SELECT @iPageSeq = MIN(PageSeq) 
			,@iMaxPageSeq = MAX(PageSeq)
		FROM [dbo].[CustomerIdXref];

		WHILE @iPageSeq <= @iMaxPageSeq 
		BEGIN
			INSERT INTO [customer].[CustomerIdXref](
				 CustomerId
				,IdTypeId
				,IdStateId
				,IdEncrypted
				,IdMac
				,Last4
				,OrgId
				,StatusFlag
				,DateActivated
				,UserName
				,IdMac64
			)
			SELECT cix0.CustomerId 
				,cix0.IdTypeId
				,cix0.IdStateId
				,cix0.IdEncrypted
				,cix0.IdMac
				,cix0.Last4
				,cix0.OrgId
				,cix0.StatusFlag
				,cix0.DateActivated
				,cix0.UserName
				,cix0.IdMac64
			FROM [dbo].[CustomerIdXref] cix0
			WHERE cix0.PageSeq = @iPageSeq 
				AND EXISTS (SELECT 'X' 
						FROM [customer].[Customer] c
						WHERE cix0.CustomerId = c.CustomerId)
			ORDER BY cix0.CustomerId ASC;

			SET @iPageSeq += 1; 

			WAITFOR DELAY '00:00:01'; 
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @iErrorDetailId = -1 * @iErrorDetailId; 
		THROW;
	END CATCH	
END
