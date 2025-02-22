USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspLadderInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record or return 
	a LadderId if it already exists
   
   Tables: [riskprocessing].[Ladder]
   
   Functions: [error].[uspLogErrorDetailInsertOut]

   History:
      2015-07-08 - LBD - Created, from Validbank
	  2017-02-18 - CBS - Modified, return LadderId if it already exists
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderInsertOut](
    @pnvCode NVARCHAR(25)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piLadderId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Ladder table (
		LadderId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname
		,@iLadderId int = 0; --2017-02-18
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--2017-02-18
	--IF NOT EXISTS(SELECT 'X' 
	--FROM [riskprocessing].[Ladder]
	--WHERE [Name] = @pnvName
	--	OR Code = @pnvCode;     
		     
	SELECT @iLadderId = LadderId 
	FROM [riskprocessing].[Ladder] WITH (NOLOCK)
	WHERE [Name] = @pnvName
		OR Code = @pnvCode;
	
	IF ISNULL(@iLadderId,0) = 0
	--2017-02-18
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [riskprocessing].[Ladder]
			OUTPUT inserted.LadderId
				,inserted.Code
				,inserted.Name
				,inserted.Descr
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @Ladder
			SELECT @pnvCode
			,@pnvName
			,@pnvDescr
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderId = LadderId
			FROM @Ladder
		END
	END
	ELSE
		--SELECT @piLadderID = -3 --2017-02-18
		SET @piLadderId = @iLadderId;
END
