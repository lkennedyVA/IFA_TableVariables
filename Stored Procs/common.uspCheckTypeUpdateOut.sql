USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspCheckTypeUpdateOut]    Script Date: 1/2/2025 7:33:19 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCheckTypeUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will update the CheckType, it will not update the StatusFlag
	Tables: [common].[CheckType]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspCheckTypeUpdateOut](
	 @pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@piDisplayOrder INT = 0
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
	--Will Not update this checktype to a checktype already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [common].[CheckType]
					WHERE CheckTypeId <> @piCheckTypeId
						AND [Name] = @pnvName)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [common].[CheckType]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,DisplayOrder = ISNULL(CASE WHEN @piDisplayOrder <> 0 THEN @piDisplayOrder ELSE NULL END,DisplayOrder)
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
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[CheckType](CheckTypeId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
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
	ELSE
		SELECT @piCheckTypeId = -3
END
