USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspAddressStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the Address (Set StatusFlag)
	Tables: [common].[Address]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspAddressStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiAddressId BIGINT OUTPUT
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
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [common].[Address]
			SET StatusFlag = 1
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
			----Anytime an update occurs we place an original copy in an archive table
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
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT AddressId 
			--	,Address1
			--,Address2
			--,City
			--,StateId
			--,ZipCode
			--,ZipCodeLast4
			--	,Country
			--	,Latitude
			--	,Longitude
			--,StatusFlag
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
