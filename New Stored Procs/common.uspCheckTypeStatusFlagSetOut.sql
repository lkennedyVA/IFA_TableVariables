USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCheckTypeStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the CheckType (Set StatusFlag)
	Tables: [common].[CheckType]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspCheckTypeStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piCheckTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @CheckType table (
		 CheckTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,DisplayOrder int
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
			UPDATE [common].[CheckType]
			SET StatusFlag = 1
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.CheckTypeId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.DisplayOrder
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @CheckType
			WHERE CheckTypeId = @piCheckTypeId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[CheckType](CheckTypeId
			--	,Code
			--	,Name
			--	,Descr
			--	,DisplayOrder
			--	,StatusFlag
			--	,DateActivated
			--	,DateArchived
			--	,UserName
			--) 
			--SELECT CheckTypeId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @CheckType
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piCheckTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piCheckTypeId = CheckTypeId
			FROM @CheckType;
		END
	END
END
