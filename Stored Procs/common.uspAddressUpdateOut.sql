USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspAddressUpdateOut]    Script Date: 1/2/2025 7:27:38 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspAddressUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will update the Address, it will not update the StatusFlag
	Tables: [common].[Address]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspAddressUpdateOut](
	 @pbiAddressID BIGINT  OUTPUT
	,@pnvAddress1 NVARCHAR(150)
	,@pnvAddress2 NVARCHAR(150)
	,@pnvCity NVARCHAR(150)
	,@pnvStateAbbv NVARCHAR(2)
	,@pnvZipCode NCHAR(9)
	,@pnvCountry NVARCHAR(50)
	,@pfLatitude FLOAT = -1
	,@pfLongitude FLOAT = -1
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Address table (
		 AddressId bigint
		,Address1 nvarchar(150)
		,Address2 nvarchar(150)
		,City  nvarchar(100)
		,StateId int
		,ZipCode nchar(5)
		,ZipCodeLast4 nchar(4)
		,Country nvarchar(50)
		,Latitude float
		,Longitude float
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iStateId int
		,@iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SELECT @iStateId = s.StateId
	FROM [common].[State] s
	WHERE s.Code = @pnvStateAbbv;
	IF @iStateId IS NULL
		SET @iStateId = 0;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [common].[Address]
			SET Address1 = CASE WHEN @pnvAddress1 = N'' THEN Address1 ELSE @pnvAddress1 END
				,Address2 = CASE WHEN @pnvAddress2 = N'' THEN Address2 ELSE @pnvAddress2 END
				,City = CASE WHEN @pnvCity = N'' THEN City ELSE @pnvCity END
				,StateId = CASE WHEN ISNULL(@iStateId,0) <> 0 THEN @iStateId ELSE NULL END
				,ZipCode = CASE WHEN @pnvZipCode = N'' THEN ZipCode ELSE LEFT(@pnvZipCode,5) END
				,ZipCodeLast4 = CASE WHEN @pnvZipCode = N'' and LEN(@pnvZipCode) = 9 THEN ZipCodeLast4 ELSE RIGHT(@pnvZipCode,4) END
				,Country = CASE WHEN @pnvCountry = N'' THEN Country ELSE @pnvCountry END
				,Latitude = CASE WHEN @pfLatitude = -1 THEN Latitude ELSE @pfLatitude END
				,Longitude = CASE WHEN @pfLongitude = -1 THEN Longitude ELSE @pfLongitude END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.AddressId
				,deleted.Address1
				,deleted.Address2
				,deleted.City
				,deleted.StateId
				,deleted.ZipCode
				,deleted.ZipCodeLast4
				,deleted.Country
				,deleted.Latitude
				,deleted.Longitude
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @Address
			WHERE AddressId = @pbiAddressId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[Address](AddressId
			--,Address1
			--,Address2
			--,City
			--,StateId
			--,ZipCode
			--,ZipCodeLast4
			--	,Country
			--	,Latitude
			--	,Longitude
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT AddressId
			--,Address1
			--,Address2
			--,City
			--,StateId
			--,ZipCode
			--,ZipCodeLast4
			--	,Country
			--	,Latitude
			--	,Longitude
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @Address
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @pbiAddressId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @pbiAddressId = AddressId
			FROM @Address;
		END
	END
END
