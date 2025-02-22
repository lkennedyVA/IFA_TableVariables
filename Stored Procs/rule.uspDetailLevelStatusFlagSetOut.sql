USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDetailLevelStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2012-20-03
	Descr: This procedure will Activate the DetailLevel (Set StatusFlag)
	Tables: [rule].[DetailLevel]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2012-20-03 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspDetailLevelStatusFlagSetOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piDetailLevelID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DetailLevel table (
		 DetailLevelId int
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
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[DetailLevel]
			SET StatusFlag = 1
				,DateActivated = SYSDATETIME()
			OUTPUT deleted.DetailLevelId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.DisplayOrder
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @DetailLevel
			WHERE DetailLevelId = @piDetailLevelId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[DetailLevel](DetailLevelId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT DetailLevelId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @DetailLevel
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piDetailLevelId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piDetailLevelID = DetailLevelId
			FROM @DetailLevel;
		END
	END
END
