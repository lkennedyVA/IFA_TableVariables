USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspAddressInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [common].[Address]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
		2018-07-21 - LSW - Insert if address is new; returns AddressId of existing row or newly created row.
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspAddressInsertOut](
    @pnvAddress1 NVARCHAR(150)
	,@pnvAddress2 NVARCHAR(150)
   ,@pnvCity NVARCHAR(150)
   ,@pnvStateAbbv NVARCHAR(2)
   ,@pnvZipCode NCHAR(9)
	,@pnvCountry NVARCHAR(50)
	,@pfLatitude FLOAT
	,@pfLongitude FLOAT
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@pbiAddressId BIGINT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @Address table 
		(
			 AddressId bigint not null
			,Address1 nvarchar(150) null
			,Address2 nvarchar(150) null
			,City  nvarchar(100) null
			,StateId int null
			,ZipCode nchar(5) null
			,ZipCodeLast4 nchar(4) null
			,Country nvarchar(50) null
			,Latitude float null
			,Longitude float null
			,StatusFlag int not null
			,DateActivated datetime2(7) not null
			,UserName nvarchar(100) not null
		);
   DECLARE 
		 @iStateId int 
		,@biAddressId bigint
		,@iErrorDetailId int
      ,@iCurrentTransactionLevel int
      ,@sSchemaName nvarchar(128);
   SET @sSchemaName = N'common';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;

	SELECT @iStateId = s.StateId
	FROM [common].[State] s
	WHERE s.Code = @pnvStateAbbv;
	IF @iStateId IS NULL
		SET @iStateId = 0;
 
	SELECT @biAddressId = a.AddressId
	FROM [common].[Address] a
	WHERE a.Address1 = @pnvAddress1
		AND a.Address2 = @pnvAddress2
		AND a.City = @pnvCity
		AND a.StateId = @iStateId
		AND a.ZipCode = @pnvZipCode
		AND a.Country = @pnvCountry

	IF ISNULL( @biAddressId, -1 ) = -1
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [common].[Address]
				OUTPUT inserted.AddressId
					,inserted.Address1
					,inserted.Address2
					,inserted.City
					,inserted.StateId
					,inserted.ZipCode
					,inserted.ZipCodeLast4
					,inserted.Country
					,inserted.Latitude
					,inserted.Longitude
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @Address
			SELECT @pnvAddress1 AS Address1
				,@pnvAddress2 AS Address2
				,@pnvCity AS City
				,@iStateId AS StateId
				,LEFT(@pnvZipCode,5) AS ZipCode
				,CASE WHEN LEN(@pnvZipCode) = 9 THEN RIGHT(@pnvZipCode,4) ELSE '' END AS ZipCodeLast4
				,@pnvCountry AS Country
				,@pfLatitude AS Latitude
				,@pfLongitude AS Longitude
				,@piStatusFlag AS StatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName AS UserName
			--FROM [common].[State]
			--WHERE StateId = @iStateId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId = @iErrorDetailId OUTPUT;
			SET @pbiAddressId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @pbiAddressId = AddressId
			FROM @Address
		END
	END
END
